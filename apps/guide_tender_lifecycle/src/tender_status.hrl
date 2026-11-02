%%% Bit flags for tender_state's status field. Powers of 2, set and read with
%%% evoq_bit_flags (reckon-db-org/evoq, guides/bit_flags.md). The pursuit
%%% (#4b) adds PURSUED 16, DECLINED 32, SUBMITTED 64, WON 128 and LOST 256.
-define(TENDER_SPOTTED, 1).          %% 2^0 -- a notice fit the profile
-define(TENDER_AMENDED, 2).          %% 2^1 -- a correction reached it
-define(TENDER_AWARD_PUBLISHED, 4).  %% 2^2 -- the buyer published the award
-define(TENDER_DISMISSED, 8).        %% 2^3 -- the bid team said "not for us"
