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
  terminology_id uuid,
  rules_id uuid,
  statsheet_id uuid,
  away_score smallInt,
  home_score smallInt,
  away_team_id uuid,
  home_team_id uuid,
  away_team_odds decimal,
  home_team_odds decimal,
  season smallInt,
  is_postseason boolean,
  day smallInt,
  phase smallInt,
  innings smallInt,
  series_index smallInt,
  series_length smallInt,
  shame boolean,
  weather smallInt,
  perceived_started_at timestamp,
  perceived_ended_at timestamp
);

CREATE TYPE blaseball.event_base_runner(
  runner_id uuid,
  responsible_pitcher_id uuid,
  base_before_play tinyInt,
  base_after_play tinyInt,
  was_base_stolen boolean,
  was_caught_stealing boolean,
  was_picked_off boolean,
);

CREATE TABLE IF NOT EXISTS blaseball.game_events(
  perceived_at timestamp,
  game_id uuid,
  event_type text,
  event_index int,
  inning tinyInt,
  outs_before_play tinyInt,
  batter_id uuid,
  batter_team_id uuid,
  pitcher_id uuid,
  pitcher_team_id uuid,
  home_score smallInt,
  away_score smallInt,
  home_strike_count smallInt,
  away_strike_count smallInt,
  batter_count int,
  pitches list<varchar(1)>,
  total_strikes smallInt,
  total_balls smallInt,
  total_fouls smallInt,
  is_leadoff boolean,
  is_pinch_hit boolean,
  lineup_position smallInt, # not sure if we have access to this
  is_last_event_for_at_bat boolean,
  bases_hit tinyInt,
  runs_batted_in tinyInt,
  is_sacrifice_hit boolean,
  is_sacrifice_fly boolean,
  outs_on_play tinyInt,
  is_double_play boolean,
  is_triple_play boolean,
  is_wild_pitch boolean,
  batted_ball_type text,
  is_bunt boolean,
  errors_on_play tinyInt,
  batter_base_after_play tinyInt,
  base_runners list<FROZEN<blaseball.event_base_runner>>,
  is_last_game_event boolean,
  additional_context text,
  PRIMARY KEY (game_id, event_index)
);

