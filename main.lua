-- ──────────────────────────────────────────────────────────
-- CONSTANTS
local COLS, ROWS = 32, 32 -- grid dimensions

-- ──────────────────────────────────────────────────────────
-- LIBS + GLOBALS
local wf = require("libraries.windfield") -- Windfield physics
local world = nil
local Grid = require("grid")
local grid = nil
local Cannon = require("cannon")
local cannon = nil

local MOVE_INTERVAL = 10
local move_timer = 0
local GAME_OVER_Y = nil -- will be set in love.load
local game_over = false

score = 0

-- ──────────────────────────────────────────────────────────
function love.load()
	love.window.setTitle("Bubble Shooter – Grid Test")
	love.graphics.setBackgroundColor(0.08, 0.08, 0.09)

	local windowW, windowH = love.graphics.getDimensions()
	local cell_vstep = windowH / (ROWS + 0.5)
	local CELL_R = cell_vstep / math.sqrt(3)

	world = wf.newWorld(0, 0, false) -- No gravity
	grid = Grid.new(COLS, ROWS, CELL_R)

	local startingRows = 5 -- change this number to control how many rows appear initially
	for i = 2, startingRows do
		grid:spawnTopRow(world)
	end

	GAME_OVER_Y = windowH - windowH / 6

	local bubbleColors = grid:getPresentColors()
	cannon = Cannon:new(windowW / 2, windowH - 60, bubbleColors, world, CELL_R - 2, grid)

	world:addCollisionClass("CannonBubble")

	score = 0
end

function love.update(dt)
	if world then
		world:update(dt)
	end
	if not game_over then
		move_timer = move_timer + dt
		if move_timer >= MOVE_INTERVAL then
			move_timer = move_timer - MOVE_INTERVAL
			grid:spawnTopRow(world)
		end
		-- Check for game over: if any bubble in any row crosses GAME_OVER_Y
		for r = 0, grid.rows - 1 do
			for q = 0, grid.cols - 1 do
				local bubble = grid.bubbles[r] and grid.bubbles[r][q]
				if bubble then
					local x, y = grid:axialToPixel(q, r)
					if y + grid.r >= GAME_OVER_Y then
						game_over = true
						break
					end
				end
			end
			if game_over then
				break
			end
		end
	end

	if cannon then
		cannon:update(dt)
		cannon:handleWallBounce()
	end
end

function love.draw()
	love.graphics.setLineWidth(1)
	love.graphics.setColor(0.6, 0.6, 0.6)

	for r = 0, grid.rows - 1 do
		for q = 0, grid.cols - 1 do
			local bubble = grid.bubbles[r] and grid.bubbles[r][q]
			if bubble then
				local color = bubble
				local x, y = grid:axialToPixel(q, r)
				love.graphics.setColor(color[1], color[2], color[3])
				love.graphics.circle("fill", x, y, grid.r - 2)
				love.graphics.setColor(0.2, 0.2, 0.2)
				love.graphics.circle("line", x, y, grid.r - 2)
			end
		end
	end

	-- Draw game over line
	love.graphics.setColor(1, 0, 0)
	love.graphics.setLineWidth(3)
	love.graphics.line(0, GAME_OVER_Y, love.graphics.getWidth(), GAME_OVER_Y)

	if game_over then
		love.graphics.setColor(1, 0, 0)
		love.graphics.print("GAME OVER", 40, GAME_OVER_Y + 10, 0, 2, 2)
	end

	if cannon then
		cannon:draw()

		local nextColor = cannon:getNextColor()
		local cx, cy = cannon.x, cannon.y
		local r = cannon.bubbleRadius
		love.graphics.setColor(1, 1, 1)
		love.graphics.print("Next", cx + r * 2 + 10, cy - r - 10)
		love.graphics.setColor(nextColor[1], nextColor[2], nextColor[3])
		love.graphics.circle("fill", cx + r * 2 + 30, cy, r)
		love.graphics.setColor(0.2, 0.2, 0.2)
		love.graphics.circle("line", cx + r * 2 + 30, cy, r)
	end

	love.graphics.setColor(1, 1, 1)
	love.graphics.print("Score: " .. tostring(score), 20, 20)
end

function love.mousepressed(x, y, button)
	if button == 1 and cannon then
		cannon:shoot()
	end
end
