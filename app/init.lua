local conf = require('config')

box.once('access:v1', function()
	box.schema.user.grant('guest', 'read,write,execute', 'universe')
end)

local vk = require('vk')
package.reload:register(vk)
rawset(_G, 'vk', vk)

vk.start(conf.get('app'))
