%%% Bit flags for tender_profile_state's status field. Powers of 2, set and
%%% read with evoq_bit_flags (reckon-db-org/evoq, guides/bit_flags.md).
-define(TENDER_PROFILE_INITIATED, 1). %% 2^0 -- the realm's profile exists
-define(TENDER_PROFILE_DESCRIBED, 2). %% 2^1 -- it says what the realm looks for
