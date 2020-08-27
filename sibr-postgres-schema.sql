CREATE TABLE IF NOT EXISTS imported_logs(
  id SERIAL PRIMARY KEY,
  key text,
  imported_at timestamp
);

/*
 * Game event types:
 * UNKNOWN - An event not currently tracked.
 * NONE - No event occurred (should not use usually).
 * OUT - A generic out.
 * STRIKEOUT - The player struck out.
 * STOLEN_BASE - A player stole a base.
 * CAUGHT_STEALING - A player was caught stealing.
 * PICKOFF - A player was picked off.
 * WILD_PITCH - A wild pitch occurred.
 * BALK - The pitcher balked (umps please add balks to blaseball).
 * OTHER_ADVANCE - Some base advancement not otherwise covered here.
 * WALK - The batter was walked.
 * INTENTIONAL_WALK - The batter was intentionally walked.
 * HIT_BY_PITCH - The batter was hit by pitch.
 * FIELDERS_CHOICE - The play advanced on fielders choice.
 * SINGLE - The batter hit a single.
 * DOUBLE - The batter hit a double.
 * TRIPLE - The batter hit a triple.
 * HOME_RUN - The batter hit a home run.
 */

CREATE TABLE IF NOT EXISTS game_events(
  id SERIAL PRIMARY KEY,
  perceived_at timestamp, /* The time at which the first message that is included in this event was observed by the client. */
  game_id varchar(36), /* The ID of the game record. */
  event_type text, /* The type of event. */
  event_index int, /* The position of this event relative to the other events in the game (0-indexed). */
  inning smallint, /* The inning in which the event took place (1-indexed). */
  top_of_inning boolean, /* Did this event take place in the top or the bottom of the inning? */
  outs_before_play smallint, /* The number of outs before this event took place. */
  batter_id varchar(36), /* The ID of the batter's player record. */
  batter_team_id varchar(36), /* The ID of the batter's team record. */
  pitcher_id varchar(36), /* The ID of the pitcher's player record. */
  pitcher_team_id varchar(36), /* The ID of the pitcher's team record. */
  home_score decimal, /* The score of the home team. */
  away_score decimal, /* The score of the away team. */
  home_strike_count smallint, /* The number of strikes required to strike out a batter on the home team. */
  away_strike_count smallint, /* The number of strikes required to strike out a batter on the away team. */
  batter_count int, /* The total number of batters to take the plate in this game. */
  pitches varchar(1)[], /* The pitches in this play. See Retrosheet for symbology. */
  total_strikes smallint, /* The total number of strikes that occurred in the play. */
  total_balls smallint, /* The total number of balls that occurred in the play. */
  total_fouls smallint, /* The total number of foul balls that occurred in the play (not currently trackable). */
  is_leadoff boolean, /* Is this batter leading off the inning? */
  is_pinch_hit boolean, /* Is this batter pinch hitting? */
  lineup_position smallint, /* not sure if we have access to this */
  is_last_event_for_plate_appearance boolean, /* Is this the last event in the plate appearance? (Almost always true, false if a base is stolen for example) */
  bases_hit smallint, /* The number of bases reached in the hit. */
  runs_batted_in smallint, /* The number of runs batted in. */
  is_sacrifice_hit boolean, /* Was this a sacrifice hit? */
  is_sacrifice_fly boolean, /* Was this a sacrifice fly? */
  outs_on_play smallint, /* The number of outs that occurred from this play. */
  is_double_play boolean, /* Is this a double play? */
  is_triple_play boolean, /* Is this a triple play? */
  is_wild_pitch boolean, /* Was this event a wild pitch? */
  batted_ball_type text, /* F - fly ball, G - ground ball, L - line drive, P - pop-up. Not sure if we can track this. */
  is_bunt boolean, /* Was this play a bunt? */
  errors_on_play smallint, /* The number of errors that occurred on the play. */
  batter_base_after_play smallint, /* The number of batters on base after the play. */
  is_last_game_event boolean, /* Is this the last event in the game? */
  event_text text[], /* The message text descriptions that contributed to this event. */
  additional_context text /* Free space for your own comments. */
);

CREATE TABLE IF NOT EXISTS game_event_base_runners(
  id SERIAL PRIMARY KEY,
  game_event_id integer REFERENCES game_events(id) ON DELETE CASCADE,
  runner_id varchar(36), /* The ID of the player that is on base. */
  responsible_pitcher_id varchar(36), /* The ID of the pitcher that is responsible for the runner. */
  base_before_play int, /* The base of the runner at the start of the play (see game_events). 0 - not on base at the start of the play. */
  base_after_play int, /* The base of the runner at the end of the play (see game_events). 0 - Not on base at the end of the play. */
  was_base_stolen boolean, /* Was the base successfully stolen? */
  was_caught_stealing boolean, /* Was the runner caught stealing? */
  was_picked_off boolean /* Was the runner picked off */
);

/*
 * Player event types:
 * INCINERATION - The player was incinerated
 * PEANUT_GOOD - The player had a yummy reaction!
 * PEANUT_BAD - The player had an allergic reaction!
 */
CREATE TABLE IF NOT EXISTS player_events(
  id SERIAL PRIMARY KEY,
  game_event_id integer REFERENCES game_events(id) ON DELETE CASCADE,
  player_id varchar(36), /* The player that was affected by the event. */
  event_type text /* The type of the event. */
);

  
CREATE TABLE IF NOT EXISTS games(
  game_id varchar(36) PRIMARY KEY, /* Use the uuid as the primary key */
  day int,
  season int,
  last_game_event int,
  home_odds decimal,
  away_odds decimal,
  weather int,

  /* Things that could be calculated instead but might be nice if blaseball format changes */
  series_index int,
  series_length int,
  is_postseason bool,

  /* Things that we technically could get from looking up the last game event */
  /* (In the order that they should be here too) */
  home_team varchar(36),
  away_team varchar(36),
  home_score int,
  away_score int,
  number_of_innings int,
  ended_on_top_of_inning boolean,
  ended_in_shame boolean,

  /* Things we don't know what they do yet but may be important later */
  terminology_id varchar(36),
  rules_id varchar(36),
  statsheet_id varchar(36)
);
  
CREATE TABLE IF NOT EXISTS time_map(
	season int,
	day int ,
	first_time timestamp,
	PRIMARY KEY(season, day)
);
