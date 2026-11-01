%%% @doc The publication numbers this sensor has reported, so a sweep never
%%% reports a notice twice. BOUNDED: each number enters once, and the oldest
%%% leave past the maximum, so memory stays fixed however much TED publishes
%%% (some 3,800 notices a release day). Disposable: it is rebuilt empty on
%%% restart, which can report a day again, and company nodes deduplicate by
%%% publication number.
-module(reported_window).

-export([new/1, seen/2, mark/2, size/1]).

-export_type([window/0]).

-opaque window() :: #{max := pos_integer(), seen := #{binary() => true},
                      order := queue:queue(binary())}.

-spec new(pos_integer()) -> window().
new(Max) -> #{max => Max, seen => #{}, order => queue:new()}.

-spec seen(binary(), window()) -> boolean().
seen(Number, #{seen := Seen}) -> maps:is_key(Number, Seen).

-spec mark(binary(), window()) -> window().
mark(Number, #{seen := Seen} = W) when is_map_key(Number, Seen) ->
    W;
mark(Number, #{seen := Seen, order := Order} = W) ->
    evict(W#{seen := Seen#{Number => true}, order := queue:in(Number, Order)}).

-spec size(window()) -> non_neg_integer().
size(#{seen := Seen}) -> map_size(Seen).

%% One in, so at most one out.
evict(#{seen := Seen, max := Max} = W) when map_size(Seen) =< Max ->
    W;
evict(#{seen := Seen, order := Order} = W) ->
    {{value, Oldest}, Rest} = queue:out(Order),
    W#{seen := maps:remove(Oldest, Seen), order := Rest}.
