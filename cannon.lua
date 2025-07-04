local BARREL_LENGTH = 60
local BUBBLE_SPEED = 600

local Cannon = {}
Cannon.__index = Cannon

function Cannon:new(x, y, bubbleColors, physicsWorld, bubbleRadius, grid)
	local self = setmetatable({}, Cannon)
	self.x = x
	self.y = y
	self.bubbleColors = bubbleColors
	self.physicsWorld = physicsWorld
	self.angle = -math.pi / 2
	self.barrelLength = BARREL_LENGTH
	self.bubbleRadius = bubbleRadius
	self.currentColor = bubbleColors[math.random(#bubbleColors)]
	self.nextColor = bubbleColors[math.random(#bubbleColors)]
	self.activeBubble = nil
	self.grid = grid
	return self
end

function Cannon:loadNextBubble()
	self.currentColor = self.nextColor
	self.nextColor = self.bubbleColors[math.random(#self.bubbleColors)]
end

function Cannon:update(deltaTime)
	if self.grid and self.grid.popping_queue then
		return
	end
	local mouseX, mouseY = love.mouse.getPosition()
	self.angle = math.atan2(mouseY - self.y, mouseX - self.x)
	if self.activeBubble then
		local windowWidth = love.graphics.getWidth()
		local radius = self.bubbleRadius
		local previousX, previousY = self.activeBubble.x, self.activeBubble.y
		self.activeBubble.x = self.activeBubble.x + self.activeBubble.vx * deltaTime
		self.activeBubble.y = self.activeBubble.y + self.activeBubble.vy * deltaTime
		if self.activeBubble.x - radius < 0 then
			self.activeBubble.vx = -self.activeBubble.vx
			self.activeBubble.x = radius
		elseif self.activeBubble.x + radius > windowWidth then
			self.activeBubble.vx = -self.activeBubble.vx
			self.activeBubble.x = windowWidth - radius
		end

		-- Stepwise collision detection to prevent tunneling
		local steps = math.ceil(
			math.max(math.abs(self.activeBubble.x - previousX), math.abs(self.activeBubble.y - previousY))
				/ (radius * 0.5)
		)
		for i = 1, steps do
			local t = i / steps
			local interpolatedX = previousX + (self.activeBubble.x - previousX) * t
			local interpolatedY = previousY + (self.activeBubble.y - previousY) * t
			local column, row = self.grid:pixelToAxial(interpolatedX, interpolatedY)
			if self.grid.bubbles[row] and self.grid.bubbles[row][column] then
				local cellX, cellY = self.grid:axialToPixel(column, row)
				if (interpolatedX - cellX) ^ 2 + (interpolatedY - cellY) ^ 2 <= (2 * radius) ^ 2 then
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
					local attachColumn, attachRow = nil, nil
					for _, neighbor in ipairs(getNeighbors(column, row)) do
						local neighborColumn, neighborRow = neighbor[1], neighbor[2]
						if self.grid.bubbles[neighborRow] and not self.grid.bubbles[neighborRow][neighborColumn] then
							attachColumn, attachRow = neighborColumn, neighborRow
							break
						end
					end
					if not attachColumn or not attachRow then
						local minDist, minColumn, minRow = math.huge, nil, nil
						for rowIndex = 0, self.grid.rows - 1 do
							for columnIndex = 0, self.grid.cols - 1 do
								if not self.grid.bubbles[rowIndex][columnIndex] then
									local cellX2, cellY2 = self.grid:axialToPixel(columnIndex, rowIndex)
									local dist = (interpolatedX - cellX2) ^ 2 + (interpolatedY - cellY2) ^ 2
									if dist < minDist then
										minDist = dist
										minColumn, minRow = columnIndex, rowIndex
									end
								end
							end
						end
						attachColumn, attachRow = minColumn, minRow
					end
					if attachColumn and attachRow then
						self.grid.bubbles[attachRow][attachColumn] = self.activeBubble.color
						local popped = self.grid:checkAndRemoveMatches(attachColumn, attachRow, self.physicsWorld)
						if popped and popped > 0 and _G.SCORE then
							_G.SCORE = _G.SCORE + popped * 10
						end
						self.activeBubble = nil
						self:loadNextBubble()
					end
					return
				end
			end
		end
		-- Top row snap
		if self.activeBubble and self.activeBubble.y - radius <= self.grid.originY then
			local column, row = self.grid:pixelToAxial(self.activeBubble.x, self.activeBubble.y)
			if not self.grid.bubbles[row][column] then
				self.grid.bubbles[row][column] = self.activeBubble.color
				local popped = self.grid:checkAndRemoveMatches(column, row, self.physicsWorld)
				if popped and popped > 0 and _G.SCORE then
					_G.SCORE = _G.SCORE + popped * 10
				end
				self.activeBubble = nil
				self:loadNextBubble()
			end
		end
		if self.activeBubble and self.activeBubble.y + radius < 0 then
			self.activeBubble = nil
			self:loadNextBubble()
		end
	end
end

function Cannon:shoot()
	if self.activeBubble then
		return
	end
	local bubbleStartX = self.x + math.cos(self.angle) * self.barrelLength
	local bubbleStartY = self.y + math.sin(self.angle) * self.barrelLength
	self.activeBubble = {
		x = bubbleStartX,
		y = bubbleStartY,
		vx = math.cos(self.angle) * BUBBLE_SPEED,
		vy = math.sin(self.angle) * BUBBLE_SPEED,
		color = self.currentColor,
	}
end

function Cannon:draw()
	love.graphics.setColor(0.8, 0.8, 0.8)
	love.graphics.setLineWidth(10)
	love.graphics.line(
		self.x,
		self.y,
		self.x + math.cos(self.angle) * self.barrelLength,
		self.y + math.sin(self.angle) * self.barrelLength
	)
	love.graphics.setLineWidth(1)

	-- Guide line
	local windowWidth, windowHeight = love.graphics.getWidth(), love.graphics.getHeight()
	local radius = self.bubbleRadius
	local x = self.x + math.cos(self.angle) * self.barrelLength
	local y = self.y + math.sin(self.angle) * self.barrelLength
	local vx = math.cos(self.angle)
	local vy = math.sin(self.angle)
	local speed = BUBBLE_SPEED
	vx = vx * speed
	vy = vy * speed
	local points = { x, y }
	for i = 1, 3 do
		local t = nil
		if vx < 0 then
			t = (radius - x) / vx
		elseif vx > 0 then
			t = (windowWidth - radius - x) / vx
		end
		if not t or t < 0 then
			break
		end
		x = x + vx * t
		y = y + vy * t
		table.insert(points, x)
		table.insert(points, y)
		vx = -vx
	end
	love.graphics.setColor(1, 1, 1, 0.3)
	love.graphics.setLineWidth(2)
	love.graphics.line(points)
	love.graphics.setLineWidth(1)

	love.graphics.setColor(self.currentColor[1], self.currentColor[2], self.currentColor[3])
	love.graphics.circle("fill", self.x, self.y, self.bubbleRadius)
	love.graphics.setColor(0.2, 0.2, 0.2)
	love.graphics.circle("line", self.x, self.y, self.bubbleRadius)
	if self.activeBubble then
		love.graphics.setColor(self.activeBubble.color[1], self.activeBubble.color[2], self.activeBubble.color[3])
		love.graphics.circle("fill", self.activeBubble.x, self.activeBubble.y, self.bubbleRadius)
		love.graphics.setColor(0.2, 0.2, 0.2)
		love.graphics.circle("line", self.activeBubble.x, self.activeBubble.y, self.bubbleRadius)
	end
end

function Cannon:handleWallBounce() end

function Cannon:getNextColor()
	return self.nextColor
end

return Cannon
