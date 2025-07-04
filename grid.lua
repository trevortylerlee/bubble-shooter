local NUM_BUBBLE_COLORS = 3
local COLOR_OPTIONS = { { 1, 0, 0 }, { 0, 1, 0 }, { 0, 0, 1 }, { 1, 1, 0 }, { 1, 0, 1 }, { 0, 1, 1 } }

local Grid = {}
Grid.__index = Grid

function Grid.new(columnCount, rowCount, bubbleRadius)
	local self = setmetatable({}, Grid)
	self.cols = columnCount
	self.rows = rowCount
	self.r = bubbleRadius
	self.d = bubbleRadius * 2
	self.vstep = bubbleRadius * math.sqrt(3)

	local colorOptions = { unpack(COLOR_OPTIONS, 1, NUM_BUBBLE_COLORS) }
	self.bubbles = {}
	for rowIndex = 0, rowCount - 1 do
		self.bubbles[rowIndex] = {}
		for columnIndex = 0, columnCount - 1 do
			if columnIndex < 4 or columnIndex >= columnCount - 4 then
				self.bubbles[rowIndex][columnIndex] = nil
			elseif rowIndex < 10 then
				self.bubbles[rowIndex][columnIndex] = colorOptions[math.random(#colorOptions)]
			else
				self.bubbles[rowIndex][columnIndex] = nil
			end
		end
	end

	self.score_popups = {}

	-- Grid dimensions in pixels (for odd-q layout)
	local gridWidth = (columnCount - 1) * (1.5 * bubbleRadius) + bubbleRadius * 2
	local gridHeight = self.vstep * rowCount + self.vstep * 0.5

	local windowWidth, windowHeight = love.graphics.getDimensions()
	self.originX = (windowWidth - gridWidth) / 2
	self.originY = 0

	return self
end

-- Converts axial (odd-q) coordinates to pixel positions
function Grid:axialToPixel(column, row)
	local x = self.r * 3 / 2 * column
	local y = self.vstep * (row + 0.5 * (column % 2))
	return x + self.originX, y + self.originY
end

function Grid:spawnTopRow(physicsWorld)
	local colorOptions = { unpack(COLOR_OPTIONS, 1, NUM_BUBBLE_COLORS) }
	local newRow = {}
	for column = 0, self.cols - 1 do
		if column < 4 or column >= self.cols - 4 then
			newRow[column] = nil
		else
			local color = colorOptions[math.random(#colorOptions)]
			newRow[column] = color
		end
	end
	-- Shift all rows down
	for row = self.rows - 2, 0, -1 do
		self.bubbles[row + 1] = self.bubbles[row]
	end
	self.bubbles[0] = newRow
end

function Grid:findNearestCell(x, y)
	local minDist, minColumn, minRow = math.huge, nil, nil
	for row = 0, self.rows - 1 do
		for column = 0, self.cols - 1 do
			local cellX, cellY = self:axialToPixel(column, row)
			local dx, dy = x - cellX, y - cellY
			local dist = dx * dx + dy * dy
			if dist < minDist then
				minDist = dist
				minColumn, minRow = column, row
			end
		end
	end
	return minColumn, minRow
end

function Grid:pixelToAxial(x, y)
	return self:findNearestCell(x, y)
end

function Grid:checkAndRemoveMatches(column, row, physicsWorld)
	local function inBounds(col, rw)
		return col >= 0 and col < self.cols and rw >= 0 and rw < self.rows
	end
	local function sameColor(a, b)
		if not a or not b then
			return false
		end
		return a[1] == b[1] and a[2] == b[2] and a[3] == b[3]
	end

	-- Parity-aware neighbor offsets for odd-q vertical layout
	local function getNeighbors(col, rw)
		if col % 2 == 0 then
			return {
				{ col + 1, rw },
				{ col, rw + 1 },
				{ col - 1, rw },
				{ col - 1, rw - 1 },
				{ col, rw - 1 },
				{ col + 1, rw - 1 },
			}
		else
			return {
				{ col + 1, rw },
				{ col + 1, rw + 1 },
				{ col, rw + 1 },
				{ col - 1, rw + 1 },
				{ col - 1, rw },
				{ col, rw - 1 },
			}
		end
	end

	-- 1. Flood fill for color match
	local visited = {}
	for rowIndex = 0, self.rows - 1 do
		visited[rowIndex] = {}
	end
	local color = self.bubbles[row][column]
	if not color then
		return
	end
	local group = {}
	local stack = { { column, row } }
	visited[row][column] = true
	while #stack > 0 do
		local node = table.remove(stack)
		local currentColumn, currentRow = node[1], node[2]
		table.insert(group, { currentColumn, currentRow })
		for _, neighbor in ipairs(getNeighbors(currentColumn, currentRow)) do
			local neighborColumn, neighborRow = neighbor[1], neighbor[2]
			if
				inBounds(neighborColumn, neighborRow)
				and not visited[neighborRow][neighborColumn]
				and sameColor(self.bubbles[neighborRow][neighborColumn], color)
			then
				visited[neighborRow][neighborColumn] = true
				table.insert(stack, { neighborColumn, neighborRow })
			end
		end
	end

	local removed = false
	local popped = 0
	if #group >= 3 then
		for _, pos in ipairs(group) do
			local groupColumn, groupRow = pos[1], pos[2]
			self.bubbles[groupRow][groupColumn] = nil
			if
				physicsWorld
				and physicsWorld.bubbleBodies
				and physicsWorld.bubbleBodies[groupRow]
				and physicsWorld.bubbleBodies[groupRow][groupColumn]
			then
				physicsWorld.bubbleBodies[groupRow][groupColumn]:destroy()
				physicsWorld.bubbleBodies[groupRow][groupColumn] = nil
			end
			self:addScorePopup(groupColumn, groupRow, 10)
			popped = popped + 1
		end
		removed = true
	end

	if not removed then
		return
	end

	-- 2. Flood fill from top row to mark connected bubbles
	local connected = {}
	for rowIndex = 0, self.rows - 1 do
		connected[rowIndex] = {}
	end
	local queue = {}
	for columnIndex = 0, self.cols - 1 do
		if self.bubbles[0][columnIndex] then
			connected[0][columnIndex] = true
			table.insert(queue, { columnIndex, 0 })
		end
	end
	while #queue > 0 do
		local node = table.remove(queue, 1)
		local currentColumn, currentRow = node[1], node[2]
		for _, neighbor in ipairs(getNeighbors(currentColumn, currentRow)) do
			local neighborColumn, neighborRow = neighbor[1], neighbor[2]
			if
				inBounds(neighborColumn, neighborRow)
				and self.bubbles[neighborRow][neighborColumn]
				and not connected[neighborRow][neighborColumn]
			then
				connected[neighborRow][neighborColumn] = true
				table.insert(queue, { neighborColumn, neighborRow })
			end
		end
	end

	-- 3. Remove floating bubbles
	for rowIndex = 0, self.rows - 1 do
		for columnIndex = 0, self.cols - 1 do
			if self.bubbles[rowIndex][columnIndex] and not connected[rowIndex][columnIndex] then
				self.bubbles[rowIndex][columnIndex] = nil
				if
					physicsWorld
					and physicsWorld.bubbleBodies
					and physicsWorld.bubbleBodies[rowIndex]
					and physicsWorld.bubbleBodies[rowIndex][columnIndex]
				then
					physicsWorld.bubbleBodies[rowIndex][columnIndex]:destroy()
					physicsWorld.bubbleBodies[rowIndex][columnIndex] = nil
				end
				self:addScorePopup(columnIndex, rowIndex, 10)
				popped = popped + 1
			end
		end
	end
	return popped
end

function Grid:getPresentColors()
	local present = {}
	local unique = {}
	for row = 0, self.rows - 1 do
		for column = 0, self.cols - 1 do
			local bubble = self.bubbles[row][column]
			if bubble then
				local key = table.concat(bubble, ",")
				if not unique[key] then
					unique[key] = true
					table.insert(present, bubble)
				end
			end
		end
	end
	return present
end

function Grid:addScorePopup(column, row, value)
	local x, y = self:axialToPixel(column, row)
	table.insert(self.score_popups, { x = x, y = y, value = value or 10, timer = 0, alpha = 1 })
end

return Grid
