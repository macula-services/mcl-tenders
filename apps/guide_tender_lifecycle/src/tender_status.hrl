%%% Bit flags for tender_state's status field. Powers of 2, set and read with
%%% evoq_bit_flags (reckon-db-org/evoq, guides/bit_flags.md).
-define(TENDER_SPOTTED, 1).          %% 2^0 -- a notice fit the profile
-define(TENDER_AMENDED, 2).          %% 2^1 -- a correction reached it
-define(TENDER_AWARD_PUBLISHED, 4).  %% 2^2 -- the buyer published the award
-define(TENDER_DISMISSED, 8).        %% 2^3 -- the bid team said "not for us"
%% The pursuit (#4b): bid/no-bid, then won or lost.
-define(TENDER_PURSUED, 16).         %% 2^4 -- the bid team goes for it
-define(TENDER_DECLINED, 32).        %% 2^5 -- pursued, then no bid after all
-define(TENDER_BID_SUBMITTED, 64).   %% 2^6 -- the bid went in
-define(TENDER_WON, 128).            %% 2^7 -- the realm won it
-define(TENDER_LOST, 256).           %% 2^8 -- the realm lost it
