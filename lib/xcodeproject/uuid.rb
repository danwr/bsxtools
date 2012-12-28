# This UUID class is designed for use by PbxprojWriter.
class UUID
	
	def initialize
		# The first part of the UUID is generated from the time (in seconds);
		# the second/third parts come from the ethernet MAC address, if possible, otherwise
        # we substitute random numbers.
		theMAC = self.getMAC
		pid = Process.pid
		@uuid_ = [Time.now.to_i, ((pid << 16) | (theMAC >> 32)) & 0x0FFFFFFFF, (theMAC & 0x0FFFFFFFF) || prand]
		@num = self.generate
	end
	
	def getMAC
		o = `ifconfig -u en0 ether`.split(/\n\s*/)
		ether = o[1].match(/([\da-fA-F]{2}:){5}[\da-fA-F]{2}/)
		return ether[0].gsub(/:/,'').to_i(16) if ether
		0
	end
	
	def generate
		@uuid_[0] += 1
		@uuid_
	end
	
	def to_s
		"%08X%08X%08X" % @num
	end
	
	def prand
		rand 0x100000000
	end
	
	def isValid?(uuidMaybe)
		uuidMaybe.instance_of?(String) && uuidMaybe.length == 24 && uuidMaybe.match(/[0-9A-F]{24}/)
	end
	
	# standardize is intended for unit testing (allowing reproducible uuid values)
	def standardize
		@uuid_[0] = 1285116226
		@uuid_[1] = 0
		@uuid_[2] = 0
	end
end

