-- ──────────────────────────────────────────────────────────
-- CONSTANTS & CONFIGURATION
local GRID_COLUMNS, GRID_ROWS = 32, 32 -- grid dimensions
local TOP_ROW_SPAWN_INTERVAL = 10

-- ──────────────────────────────────────────────────────────
-- LIBS + GLOBALS
local windfield = require("libraries.windfield")
local physicsWorld = nil
local Grid = require("grid")
local grid = nil
local Cannon = require("cannon")
local cannon = nil

local topRowSpawnTimer = 0
local gameOverLineY = nil -- will be set in love.load
local isGameOver = false

SCORE = 0

-- ──────────────────────────────────────────────────────────
function love.load()
	love.window.setTitle("Bubble Shooter – Grid Test")
	love.graphics.setBackgroundColor(0.08, 0.08, 0.09)

	local windowWidth, windowHeight = love.graphics.getDimensions()
	local cellVerticalStep = windowHeight / (GRID_ROWS + 0.5)
	local cellRadius = cellVerticalStep / math.sqrt(3)

	physicsWorld = windfield.newWorld(0, 0, false) -- No gravity
	grid = Grid.new(GRID_COLUMNS, GRID_ROWS, cellRadius)

	local initialRows = 5 -- change this number to control how many rows appear initially
	for rowIndex = 2, initialRows do
		grid:spawnTopRow(physicsWorld)
	end

	gameOverLineY = windowHeight - windowHeight / 6

	local bubbleColors = grid:getPresentColors()
	cannon = Cannon:new(windowWidth / 2, windowHeight - 60, bubbleColors, physicsWorld, cellRadius - 2, grid)

	physicsWorld:addCollisionClass("CannonBubble")

	SCORE = 0

	SOUNDS = {}
	SOUNDS.pop = love.audio.newSource("sounds/pop.mp3", "static")
	SOUNDS.shoot = love.audio.newSource("sounds/blip.wav", "static")
end

function love.update(deltaTime)
	if physicsWorld then
		physicsWorld:update(deltaTime)
	end
	if not isGameOver then
		topRowSpawnTimer = topRowSpawnTimer + deltaTime
		if topRowSpawnTimer >= TOP_ROW_SPAWN_INTERVAL then
			topRowSpawnTimer = topRowSpawnTimer - TOP_ROW_SPAWN_INTERVAL
			if grid and physicsWorld then
				grid:spawnTopRow(physicsWorld)
			end
		end
		if grid then
			for row = 0, (grid.rows or 0) - 1 do
				for column = 0, (grid.cols or 0) - 1 do
					local bubble = grid.bubbles and grid.bubbles[row] and grid.bubbles[row][column]
					if bubble and grid.axialToPixel then
						local x, y = grid:axialToPixel(column, row)
						if grid.r and y + grid.r >= gameOverLineY then
							isGameOver = true
							break
						end
					end
				end
				if isGameOver then
					break
				end
			end
		end
	end

	-- Sequential popping
	local popping, _, just_finished = false, 0, false
	if grid and grid.updatePopping then
		popping, _, just_finished = grid:updatePopping(deltaTime, physicsWorld)
	end

	if just_finished and love.graphics and love.graphics.present then
		love.graphics.present() -- force redraw for immediate visual update
	end

	if cannon and not popping then
		cannon:update(deltaTime)
		if cannon.handleWallBounce then
			cannon:handleWallBounce()
		end
	end

	-- Update score popups
	if grid and grid.score_popups then
		local to_remove = {}
		for i, popup in ipairs(grid.score_popups) do
			popup.timer = popup.timer + deltaTime
			popup.alpha = 1 - (popup.timer / 0.7)
			if popup.alpha <= 0 then
				table.insert(to_remove, i)
			end
		end
		for i = #to_remove, 1, -1 do
			table.remove(grid.score_popups, to_remove[i])
		end
	end
end

function love.draw()
	love.graphics.setLineWidth(1)
	love.graphics.setColor(0.6, 0.6, 0.6)

	if grid then
		for row = 0, (grid.rows or 0) - 1 do
			for column = 0, (grid.cols or 0) - 1 do
				local bubble = grid.bubbles and grid.bubbles[row] and grid.bubbles[row][column]
				if bubble and grid.axialToPixel then
					local color = bubble
					local x, y = grid:axialToPixel(column, row)
					if grid.r then
						love.graphics.setColor(color[1], color[2], color[3])
						love.graphics.circle("fill", x, y, grid.r - 2)
						love.graphics.setColor(0.2, 0.2, 0.2)
						love.graphics.circle("line", x, y, grid.r - 2)
					end
				end
			end
		end
	end

	-- Draw game over line
	love.graphics.setColor(1, 0, 0)
	love.graphics.setLineWidth(3)
	love.graphics.line(0, gameOverLineY, love.graphics.getWidth(), gameOverLineY)

	if isGameOver then
		love.graphics.setColor(1, 0, 0)
		love.graphics.print("GAME OVER", 40, gameOverLineY + 10, 0, 2, 2)
	end

	if cannon then
		cannon:draw()

		if cannon.getNextColor then
			local nextColor = cannon:getNextColor()
			local cannonX, cannonY = cannon.x, cannon.y
			local radius = cannon.bubbleRadius
			love.graphics.setColor(1, 1, 1)
			love.graphics.print("Next", cannonX + radius * 2 + 10, cannonY - radius - 10)
			love.graphics.setColor(nextColor[1], nextColor[2], nextColor[3])
			love.graphics.circle("fill", cannonX + radius * 2 + 30, cannonY, radius)
			love.graphics.setColor(0.2, 0.2, 0.2)
			love.graphics.circle("line", cannonX + radius * 2 + 30, cannonY, radius)
		end
	end

	love.graphics.setColor(1, 1, 1)
	love.graphics.print("Score: " .. tostring(SCORE), 20, 20)

	-- Draw score popups
	if grid and grid.score_popups then
		for _, popup in ipairs(grid.score_popups) do
			love.graphics.setColor(1, 1, 0, popup.alpha)
			love.graphics.print("10", popup.x - 8, popup.y - 12)
		end
	end
end

function love.mousepressed(x, y, button)
	if button == 1 and cannon and (not grid or not grid.popping_queue) then
		cannon:shoot()
		SOUNDS.shoot:play()
	end
end
