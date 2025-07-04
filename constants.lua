-- constants.lua
-- Centralized configuration and magic numbers for Bubble Shooter

local constants = {}

-- Grid configuration
constants.GRID_COLUMNS = 32
constants.GRID_ROWS = 32
constants.TOP_ROW_SPAWN_INTERVAL = 10

-- Bubble and color configuration
constants.NUM_BUBBLE_COLORS = 3
constants.COLOR_OPTIONS = {
	{ 1, 0, 0 }, -- Red
	{ 0, 1, 0 }, -- Green
	{ 0, 0, 1 }, -- Blue
	{ 1, 1, 0 }, -- Yellow
	{ 1, 0, 1 }, -- Magenta
	{ 0, 1, 1 }, -- Cyan
}

-- Cannon configuration
constants.BARREL_LENGTH = 60
constants.BUBBLE_SPEED = 600

-- Popping animation config
constants.POP_DELAY = 0.08 -- initial seconds between each bubble pop
constants.POP_ACCEL = 0.7 -- exponential speed-up factor per pop

-- UI
constants.GAME_OVER_LINE_RATIO = 1 / 6 -- Fraction of window height from bottom
constants.SCORE_POPUP_DURATION = 0.7
constants.SCORE_POPUP_VALUE = 10

-- Scoring configuration
constants.BASE_POINTS = 10
constants.GROUP_BONUS_PER_BUBBLE = 5 -- (groupSize - 3) * this
constants.FALLING_BONUS = 2 * constants.BASE_POINTS
constants.FAST_SHOT_WINDOW = 2 -- seconds
constants.SPEED_BONUS = 15
constants.COMBO_MULTIPLIER_STEP = 0.1 -- Each combo increases multiplier by this

return constants
