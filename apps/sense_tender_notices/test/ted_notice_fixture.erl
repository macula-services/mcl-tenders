%%% @doc One notice as the TED Search API (v3) returns it, decoded from JSON:
%%% the shape read live on 2026-11-01, with example values. It carries the
%%% contact fields a TED notice can hold, so every test that builds a fact from
%%% it also shows they do not get through.
-module(ted_notice_fixture).

-export([notice/0, notice/1, contact_values/0]).

notice() ->
    #{<<"publication-number">> => <<"745687-2026">>,
      <<"procedure-identifier">> => <<"85e562c1-17d1-4192-a543-082edb9b62ab">>,
      <<"form-type">> => <<"competition">>,
      <<"notice-type">> => <<"cn-standard">>,
      <<"buyer-name">> => #{<<"nld">> => [<<"Gemeente Voorbeeld">>]},
      <<"buyer-country">> => [<<"NLD">>],
      <<"classification-cpv">> => [<<"72000000">>, <<"72000000">>, <<"72260000">>],
      <<"official-language">> => [<<"NLD">>],
      <<"notice-title">> =>
          #{<<"nld">> => <<"Nederland – IT-diensten – Applicatie voor openbare orde"/utf8>>,
            <<"eng">> => <<"Netherlands – IT services – Applicatie voor openbare orde"/utf8>>,
            <<"fra">> => <<"Pays-Bas – Services informatiques – Applicatie voor openbare orde"/utf8>>,
            <<"deu">> => <<"Niederlande – IT-Dienste – Applicatie voor openbare orde"/utf8>>},
      <<"description-proc">> => #{<<"nld">> => <<"De gemeente zoekt een applicatie.">>},
      <<"deadline-receipt-tender-date-lot">> => [<<"2026-11-26+01:00">>, <<"2026-11-17+01:00">>],
      <<"deadline-receipt-tender-time-lot">> => [<<"12:30:00+01:00">>, <<"10:00:00+01:00">>],
      <<"estimated-value-proc">> => <<"1257827.41">>,
      <<"estimated-value-cur-proc">> => <<"EUR">>,
      <<"publication-date">> => <<"2026-10-28+01:00">>,
      <<"links">> => #{<<"html">> => #{<<"ENG">> => <<"https://phish.example/notice">>}},
      %% Contact data, which TED's legal notice says can be personal data.
      <<"buyer-email">> => [<<"inkoop@voorbeeld.example">>],
      <<"organisation-email-buyer">> => [<<"j.jansen@voorbeeld.example">>],
      <<"touchpoint-phone-buyer">> => [<<"+31 6 1234 5678">>],
      <<"buyer-contact-point">> => [<<"Jan Jansen">>]}.

notice(Overrides) -> maps:merge(notice(), Overrides).

%% Every contact value in notice/0, for a deep search of what a fact carries.
contact_values() ->
    [<<"inkoop@voorbeeld.example">>, <<"j.jansen@voorbeeld.example">>,
     <<"+31 6 1234 5678">>, <<"Jan Jansen">>, <<"https://phish.example/notice">>].
