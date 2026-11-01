%%% @doc PROCESS MANAGER: on `tender_notice_reported_v1', maybe spot a tender.
%%%
%%% A macula_subscriber on the realm's one fact topic, sealed under the realm's
%%% tenders group, with the realm's `mcl-tenders' org as its only sources
%%% (T4): the realm's own sensors, whatever their node ids. It reads each
%%% notice again (tender_notice) and dispatches by its type:
%%%
%%%   contract_notice, prior_information  -> spot_tender, if tender_fit passes
%%%                                          and today's intake is under the cap
%%%   correction                          -> amend_tender
%%%   award                               -> note_tender_award
%%%
%%% A notice that does not fit leaves no event, nor does a correction or an
%%% award of a tender that was never spotted. Nothing of a notice reaches a
%%% log: the matches draw the profile's outline (A2).
%%%
%%% It makes no call to anyone: it reads the profile in process and dispatches
%%% in process (T1).
%%% @end
-module(on_tender_notice_reported_v1_maybe_spot_tender).
-behaviour(macula_subscriber).

-export([init/1, handle_event/4, handle_unopened/3, terminate/2]).
-export([handled/2]).

-type deps() :: #{realm := fun(() -> {ok, <<_:256>>} | {error, term()}),
                  profile := fun((<<_:256>>) -> {ok, get_tender_profile:profile()} | {error, term()}),
                  admit := fun(() -> ok | capped),
                  noted := fun(() -> ok),
                  dispatch := fun((atom(), term()) -> {ok, non_neg_integer(), [map()]} | {error, term()})}.

init(_Args) -> {ok, live()}.

handle_event(_Topic, Payload, _Meta, Deps) ->
    _ = handled(Payload, Deps),
    {noreply, Deps}.

%% Once per unopened event, naming its publisher and why, never a payload.
handle_unopened(_Topic, #{publisher := Publisher, reason := Reason}, Deps) ->
    logger:notice("[tenders] a tender notice could not be opened (~0p) from ~ts",
                  [Reason, binary:encode_hex(Publisher, lowercase)]),
    {noreply, Deps}.

terminate(_Reason, _Deps) -> ok.

%% @doc What one fact came to: the desk it went to and how, or why it went
%% nowhere. The process manager's whole decision, with its dependencies given,
%% so a test can drive it without a mesh.
-spec handled(map(), deps()) -> {atom(), term()}.
handled(Payload, #{noted := Noted, realm := Realm} = Deps) ->
    ok = Noted(),
    read(tender_notice:from_fact(Payload), Realm(), Deps).

read({skip, Why}, _Realm, _Deps) -> {skipped, Why};
read({ok, _Notice}, {error, _}, _Deps) -> {skipped, no_realm};
read({ok, #{notice_type := Type} = Notice}, {ok, Realm}, Deps) -> typed(Type, Notice, Realm, Deps).

typed(<<"correction">>, Notice, Realm, Deps) ->
    sent(amend_tender, amend_tender_v1:new(#{realm => Realm, notice => Notice}), Deps);
typed(<<"award">>, Notice, Realm, Deps) ->
    sent(note_tender_award, note_tender_award_v1:new(#{realm => Realm, notice => Notice}), Deps);
typed(_Spottable, Notice, Realm, #{profile := Profile} = Deps) ->
    profiled(Profile(Realm), Notice, Realm, Deps).

profiled({ok, Profile}, Notice, Realm, Deps) -> fitted(tender_fit:fit(Notice, Profile), Notice, Realm, Deps);
profiled({error, _}, _Notice, _Realm, _Deps) -> {skipped, no_profile}.

fitted({no_fit, Why}, _Notice, _Realm, _Deps) ->
    {skipped, {no_fit, Why}};
fitted({fits, Reasons}, Notice, Realm, #{admit := Admit} = Deps) ->
    admitted(Admit(), spot_tender_v1:new(#{realm => Realm, notice => Notice, reasons => Reasons}), Deps).

admitted(capped, _Cmd, _Deps) -> {skipped, capped};
admitted(ok, Cmd, Deps) -> sent(spot_tender, Cmd, Deps).

sent(Desk, {ok, Cmd}, #{dispatch := Dispatch}) -> outcome(Desk, Dispatch(Desk, Cmd));
sent(_Desk, {error, Why}, _Deps) -> {skipped, Why}.

%% A tender already spotted, a correction of one never spotted: the expected
%% answers of a repeated or unrelated notice, not faults. Anything else is the
%% service's own fault, logged by its reason alone.
outcome(Desk, {ok, _Version, _Events}) -> {Desk, ok};
outcome(Desk, {error, Expected}) when Expected =:= already_spotted; Expected =:= not_spotted;
                                       Expected =:= already_noted ->
    {Desk, Expected};
outcome(Desk, {error, Reason}) ->
    logger:warning("[tenders] ~ts refused a reported notice: ~0p", [Desk, reason(Reason)]),
    {Desk, {error, reason(Reason)}}.

reason(Reason) when is_atom(Reason) -> Reason;
reason({Tag, _}) when is_atom(Tag) -> Tag;
reason(_Other) -> internal_error.

live() ->
    #{realm => fun mcl_om:realm/0,
      profile => fun get_tender_profile:find/1,
      admit => fun tender_intake:admit/0,
      noted => fun tender_intake:noted/0,
      dispatch => fun dispatch/2}.

dispatch(spot_tender, Cmd) -> maybe_spot_tender:dispatch(Cmd);
dispatch(amend_tender, Cmd) -> maybe_amend_tender:dispatch(Cmd);
dispatch(note_tender_award, Cmd) -> maybe_note_tender_award:dispatch(Cmd).
