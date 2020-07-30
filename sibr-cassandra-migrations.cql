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
  id uuid PRIMARY KEY,
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
  active boolean
);

CREATE TABLE IF NOT EXISTS blaseball.teams(
  id uuid PRIMARY KEY,
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
  active boolean
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

CREATE TABLE IF NOT EXISTS blaseball.game_events_numeric(
  perceived_time timestamp,
  game_id uuid,
  event_type text,
  player_id uuid,
  inning smallInt,
  numeric_value decimal,
  string_value text,
  PRIMARY KEY (game_id, perceived_time)
);
