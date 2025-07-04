local Cannon = {}
Cannon.__index = Cannon

function Cannon:new(x, y, bubbleColors, world, bubbleRadius, grid)
	local self = setmetatable({}, Cannon)
	self.x = x
	self.y = y
	self.bubbleColors = bubbleColors
	self.world = world
	self.angle = -math.pi / 2
	self.barrelLength = 60
	self.bubbleRadius = bubbleRadius
	self.currentColor = bubbleColors[math.random(#bubbleColors)]
	self.nextColor = bubbleColors[math.random(#bubbleColors)]
	self.bubble = nil
	self.grid = grid
	return self
end

function Cannon:loadBubble()
	self.currentColor = self.nextColor
	self.nextColor = self.bubbleColors[math.random(#self.bubbleColors)]
end

function Cannon:update(dt)
	local mx, my = love.mouse.getPosition()
	self.angle = math.atan2(my - self.y, mx - self.x)
	if self.bubble then
		local W = love.graphics.getWidth()
		local r = self.bubbleRadius
		local prevX, prevY = self.bubble.x, self.bubble.y
		self.bubble.x = self.bubble.x + self.bubble.vx * dt
		self.bubble.y = self.bubble.y + self.bubble.vy * dt
		if self.bubble.x - r < 0 then
			self.bubble.vx = -self.bubble.vx
			self.bubble.x = r
		elseif self.bubble.x + r > W then
			self.bubble.vx = -self.bubble.vx
			self.bubble.x = W - r
		end

		-- Stepwise collision detection to prevent tunneling
		local steps = math.ceil(math.max(math.abs(self.bubble.x - prevX), math.abs(self.bubble.y - prevY)) / (r * 0.5))
		for i = 1, steps do
			local t = i / steps
			local ix = prevX + (self.bubble.x - prevX) * t
			local iy = prevY + (self.bubble.y - prevY) * t
			local q, row = self.grid:pixelToAxial(ix, iy)
			if self.grid.bubbles[row] and self.grid.bubbles[row][q] then
				local cx, cy = self.grid:axialToPixel(q, row)
				if (ix - cx) ^ 2 + (iy - cy) ^ 2 <= (2 * r) ^ 2 then
					-- Parity-aware neighbor search
					local function getNeighbors(qq, rr)
						if qq % 2 == 0 then
							return {
								{ qq + 1, rr },
								{ qq, rr + 1 },
								{ qq - 1, rr },
								{ qq - 1, rr - 1 },
								{ qq, rr - 1 },
								{ qq + 1, rr - 1 },
							}
						else
							return {
								{ qq + 1, rr },
								{ qq + 1, rr + 1 },
								{ qq, rr + 1 },
								{ qq - 1, rr + 1 },
								{ qq - 1, rr },
								{ qq, rr - 1 },
							}
						end
					end
					local attachQ, attachR = nil, nil
					for _, nbr in ipairs(getNeighbors(q, row)) do
						local nq, nr = nbr[1], nbr[2]
						if self.grid.bubbles[nr] and not self.grid.bubbles[nr][nq] then
							attachQ, attachR = nq, nr
							break
						end
					end
					if not attachQ or not attachR then
						-- If no empty neighbor, snap to nearest empty cell
						local minDist, minQ, minR = math.huge, nil, nil
						for rr = 0, self.grid.rows - 1 do
							for qq = 0, self.grid.cols - 1 do
								if not self.grid.bubbles[rr][qq] then
									local cx2, cy2 = self.grid:axialToPixel(qq, rr)
									local dist = (ix - cx2) ^ 2 + (iy - cy2) ^ 2
									if dist < minDist then
										minDist = dist
										minQ, minR = qq, rr
									end
								end
							end
						end
						attachQ, attachR = minQ, minR
					end
					if attachQ and attachR then
						self.grid.bubbles[attachR][attachQ] = self.bubble.color
						local popped = self.grid:checkAndRemoveMatches(attachQ, attachR, self.world)
						if popped and popped > 0 and _G.score then
							_G.score = _G.score + popped * 10
						end
						self.bubble = nil
						self:loadBubble()
					end
					return
				end
			end
		end
		-- Top row snap
		if self.bubble and self.bubble.y - r <= self.grid.originY then
			local q, row = self.grid:pixelToAxial(self.bubble.x, self.bubble.y)
			if not self.grid.bubbles[row][q] then
				self.grid.bubbles[row][q] = self.bubble.color
				local popped = self.grid:checkAndRemoveMatches(q, row, self.world)
				if popped and popped > 0 and _G.score then
					_G.score = _G.score + popped * 10
				end
				self.bubble = nil
				self:loadBubble()
			end
		end
		if self.bubble and self.bubble.y + r < 0 then
			self.bubble = nil
			self:loadBubble()
		end
	end
end

function Cannon:shoot()
	if self.bubble then
		return
	end
	local bx = self.x + math.cos(self.angle) * self.barrelLength
	local by = self.y + math.sin(self.angle) * self.barrelLength
	local speed = 600
	self.bubble = {
		x = bx,
		y = by,
		vx = math.cos(self.angle) * speed,
		vy = math.sin(self.angle) * speed,
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
	local W, H = love.graphics.getWidth(), love.graphics.getHeight()
	local r = self.bubbleRadius
	local x = self.x + math.cos(self.angle) * self.barrelLength
	local y = self.y + math.sin(self.angle) * self.barrelLength
	local vx = math.cos(self.angle)
	local vy = math.sin(self.angle)
	local speed = 600
	vx = vx * speed
	vy = vy * speed
	local points = { x, y }
	for i = 1, 3 do
		local t = nil
		if vx < 0 then
			t = (r - x) / vx
		elseif vx > 0 then
			t = (W - r - x) / vx
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
	if self.bubble then
		love.graphics.setColor(self.bubble.color[1], self.bubble.color[2], self.bubble.color[3])
		love.graphics.circle("fill", self.bubble.x, self.bubble.y, self.bubbleRadius)
		love.graphics.setColor(0.2, 0.2, 0.2)
		love.graphics.circle("line", self.bubble.x, self.bubble.y, self.bubbleRadius)
	end
end

function Cannon:handleWallBounce() end

function Cannon:getNextColor()
	return self.nextColor
end

return Cannon
