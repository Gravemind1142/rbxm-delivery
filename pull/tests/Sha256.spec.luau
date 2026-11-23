local ReplicatedStorage = game:GetService("ReplicatedStorage")
local JestGlobals = require(ReplicatedStorage.DevPackages.JestGlobals)
local describe, it, expect = JestGlobals.describe, JestGlobals.it, JestGlobals.expect

local Sha256 = require(ReplicatedStorage.RbxmPull.Apply.Sha256)

describe("Sha256", function()
	it("matches the FIPS 180-4 test vectors", function()
		expect(Sha256.hex("")).toBe("e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855")
		expect(Sha256.hex("abc")).toBe("ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad")
		expect(Sha256.hex("abcdbcdecdefdefgefghfghighijhijkijkljklmklmnlmnomnopnopq")).toBe(
			"248d6a61d20638b8e5c026930c3e6039a33ce45964ff2167f6ecedd419db06c1"
		)
		expect(Sha256.hex(string.rep("a", 1000000))).toBe(
			"cdc76e5c9914fb9281a1c7e284d73e67f1809a48a497200e046d39ccc7112cd0"
		)
	end)

	it("handles every padding boundary", function()
		-- Lengths around the 55/56/64-byte boundaries; digests from `sha256sum`.
		local expected = {
			[55] = "d5e285683cd4efc02d021a5c62014694958901005d6f71e89e0989fac77e4072",
			[56] = "04c26261370ee7541549d16dee320c723e3fd14671e66a099afe0a377c16888e",
			[63] = "75220b47218278e656f2013bb8f0c455a25eaf01e86c64924e9d48d89776d6f2",
			[64] = "7ce100971f64e7001e8fe5a51973ecdfe1ced42befe7ee8d5fd6219506b5393c",
			[65] = "9537c5fdf120482f7d58d25e9ed583f52c02b4e304ea814db1633ad565aed7e9",
		}
		for length, digest in expected do
			expect(Sha256.hex(string.rep("x", length))).toBe(digest)
		end
	end)

	it("accepts buffers and binary data", function()
		local data = buffer.create(256)
		for i = 0, 255 do
			buffer.writeu8(data, i, i)
		end
		expect(Sha256.hex(data)).toBe(Sha256.hex(buffer.tostring(data)))
		expect(Sha256.hex(data)).toBe("40aff2e9d2d8922e47afd4648e6967497158785fbd1da870e7110266bf944880")
	end)

	it("hashes a few MB quickly enough for a plugin", function()
		local data = buffer.create(4 * 1024 * 1024)
		local start = os.clock()
		Sha256.hex(data)
		local elapsed = os.clock() - start
		print(string.format("Sha256: 4 MiB in %.3f s", elapsed))
		expect(elapsed < 5).toBe(true)
	end)
end)
