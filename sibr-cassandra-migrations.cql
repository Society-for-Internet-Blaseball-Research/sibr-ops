CREATE KEYSPACE IF NOT EXISTS blaseball WITH replication = { 'class': 'SimpleStrategy', 'replication_factor': 1 };

CREATE TABLE IF NOT EXISTS blaseball.leagues(
  id uuid PRIMARY KEY,
  name text,
  subleague_ids set<uuid>
);

CREATE TABLE IF NOT EXISTS blaseball.subleagues(
  id uuid PRIMARY KEY,
  name text,
);

CREATE TABLE IF NOT EXISTS blaseball.players(
  id uuid,
  name text,
  anticapitalism decimal,
  baseThirst decimal,
  buoyancy decimal,
  chasiness decimal,
  coldness decimal,
  continuation decimal,
  divinity decimal,
  groundFriction decimal,
  indulgence decimal,
  laserlikeness decimal,
  martyrdom decimal,
  moxie decimal,
  musclitude decimal,
  omniscience decimal,
  overpowerment decimal,
  patheticism decimal,
  ruthlessness decimal,
  shakespearianism decimal,
  suppression decimal,
  tenaciousness decimal,
  thwackability decimal,
  tragicness decimal,
  unthwackability decimal,
  watchfulness decimal,
  pressurization decimal,
  totalFingers smallInt,
  soul smallInt,
  deceased boolean,
  started_career_at timestamp,
  ended_career_at timestamp,
  active boolean,
  perceived_at timestamp,
  PRIMARY KEY (id, perceived_at)
);

CREATE TABLE IF NOT EXISTS blaseball.teams(
  id uuid,
  division_id uuid,
  fullName text,
  location text,
  mainColor text,
  nickname text,
  secondaryColor text,
  shorthand text,
  emoji text,
  slogan text,
  shameRuns smallInt,
  totalShames smallInt,
  totalShamings smallInt,
  seasonShames smallInt,
  seasonShamings smallInt,
  championships smallInt,
  active boolean,
  perceived_at timestamp,
  PRIMARY KEY (id, perceived_at)
);

CREATE TABLE IF NOT EXISTS blaseball.team_members(
  id uuid PRIMARY KEY,
  team_id uuid, 
  player_id uuid,
  started_at timestamp,
  ended_at timestamp,
);

CREATE TABLE IF NOT EXISTS blaseball.games(
  id uuid PRIMARY KEY,
  terminology_id uuid, // The ID of the terminology record (as provided in the raw message)
  rules_id uuid, // The ID of the rules record (as provided in the raw message)
  statsheet_id uuid, // The ID of the statsheet record (as provided in the raw message)
  away_score decimal, // The number of runs scored by the away team.
  home_score decimal, // The number of run scored by the home team.
  away_team_id uuid, // The ID of the away team record.
  home_team_id uuid, // The ID of the home team record.
  away_team_odds decimal, // The odds for the away team.
  home_team_odds decimal, // The odds for the home team.
  season smallInt, // The current season (1-indexed).
  is_postseason boolean, // Is this game in the postseason?
  day smallInt, // The day of the season (1-indexed).
  phase smallInt, // The phase of the season.
  innings smallInt, // The number of innings in the game.
  series_index smallInt, // What game in the series this is (1-indexed).
  series_length smallInt, // The number of games in the series.
  shame boolean, // Did this game end in shame?
  weather text, // The weather for this game.
  perceived_started_at timestamp, // The first time this game was seen by the client.
  perceived_ended_at timestamp // The time this game ended as seen by the client.
);

CREATE TYPE blaseball.game_event_base_runner(
  runner_id uuid, // The ID of the player that is on base.
  responsible_pitcher_id uuid, // The ID of the pitcher that is responsible for the runner.
  base_before_play tinyInt, // The base of the runner at the start of the play (see game_events). 0 - not on base at the start of the play.
  base_after_play tinyInt, // The base of the runner at the end of the play (see game_events). 0 - Not on base at the end of the play.
  was_base_stolen boolean, // Was the base successfully stolen?
  was_caught_stealing boolean, // Was the runner caught stealing?
  was_picked_off boolean, // Was the runner picked off
);

// Player event types:
// INCINERATION - The player was incinerated
// PEANUT_GOOD - The player had a yummy reaction!
// PEANUT_BAD - The player had an allergic reaction!

CREATE TYPE blaseball.player_event(
  player_id uuid, // The player that was affected by the event.
  event_type text, // The type of the event.
);

// Game event types:
// UNKNOWN - An event not currently tracked.
// NONE - No event occurred (should not use usually).
// OUT - A generic out.
// STRIKEOUT - The player struck out.
// STOLEN_BASE - A player stole a base.
// CAUGHT_STEALING - A player was caught stealing.
// PICKOFF - A player was picked off.
// WILD_PITCH - A wild pitch occurred.
// BALK - The pitcher balked (umps please add balks to blaseball).
// OTHER_ADVANCE - Some base advancement not otherwise covered here.
// WALK - The batter was walked.
// INTENTIONAL_WALK - The batter was intentionally walked.
// HIT_BY_PITCH - The batter was hit by pitch.
// FIELDERS_CHOICE - The play advanced on fielders choice.
// SINGLE - The batter hit a single.
// DOUBLE - The batter hit a double.
// TRIPLE - The batter hit a triple.
// HOME_RUN - The batter hit a home run.

CREATE TABLE IF NOT EXISTS blaseball.game_events(
  perceived_at timestamp, // The time at which the first message that is included in this event was observed by the client.
  game_id uuid, // The ID of the game record.
  event_type text, // The type of event.
  event_index int, // The position of this event relative to the other events in the game (0-indexed).
  inning tinyInt, // The inning in which the event took place (1-indexed).
  top_of_inning boolean, // Did this event take place in the top or the bottom of the inning?
  outs_before_play tinyInt, // The number of outs before this event took place.
  batter_id uuid, // The ID of the batter's player record.
  batter_team_id uuid, // The ID of the batter's team record.
  pitcher_id uuid, // The ID of the pitcher's player record.
  pitcher_team_id uuid, // The ID of the pitcher's team record.
  home_score decimal, // The score of the home team.
  away_score decimal, // The score of the away team.
  home_strike_count smallInt, // The number of strikes required to strike out a batter on the home team.
  away_strike_count smallInt, // The number of strikes required to strike out a batter on the away team.
  batter_count int, // The total number of batters to take the plate in this game.
  pitches list<text>, // The pitches in this play. See Retrosheet for symbology.
  total_strikes smallInt, // The total number of strikes that occurred in the play.
  total_balls smallInt, // The total number of balls that occurred in the play.
  total_fouls smallInt, // The total number of foul balls that occurred in the play (not currently trackable).
  is_leadoff boolean, // Is this batter leading off the inning?
  is_pinch_hit boolean, // Is this batter pinch hitting?
  lineup_position smallInt, // not sure if we have access to this
  is_last_event_for_plate_appearance boolean, // Is this the last event in the plate appearance? (Almost always true, false if a base is stolen for example)
  bases_hit tinyInt, // The number of bases reached in the hit.
  runs_batted_in tinyInt, // The number of runs batted in.
  is_sacrifice_hit boolean, // Was this a sacrifice hit?
  is_sacrifice_fly boolean, // Was this a sacrifice fly?
  outs_on_play tinyInt, // The number of outs that occurred from this play.
  is_double_play boolean, // Is this a double play?
  is_triple_play boolean, // Is this a triple play?
  is_wild_pitch boolean, // Was this event a wild pitch?
  batted_ball_type text, // F - fly ball, G - ground ball, L - line drive, P - pop-up. Not sure if we can track this.
  is_bunt boolean, // Was this play a bunt?
  errors_on_play tinyInt, // The number of errors that occurred on the play.
  batter_base_after_play tinyInt, // The number of batters on base after the play.
  base_runners list<FROZEN<blaseball.game_event_base_runner>>, // The base runners at the start and end of the play (see event_base_runner).
  is_last_game_event boolean, // Is this the last event in the game?
  player_events list<FROZEN<blaseball.player_event>>, // The player events that occurred in the play (incinerations, etc).
  event_text list<text>, // The message text descriptions that contributed to this event.
  additional_context text, // Free space for your own comments.
  PRIMARY KEY (game_id, event_index)
);

