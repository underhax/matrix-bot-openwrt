.PHONY: fmt check test coverage verify

fmt:
	stylua packages/ tests/

check:
	stylua --check packages/ tests/
	luacheck packages/matrixbot/src/ packages/luci-app-matrixbot/
	luacheck tests/
	shellcheck packages/matrixbot/src/etc/init.d/matrixbot packages/matrixbot/src/etc/profile.d/matrix-cli.sh
	lua-language-server --check=. --configpath=.luarc.json --check_format=pretty --checklevel=Information

test:
	LUA_PATH="packages/matrixbot/src/usr/lib/lua/?.lua;;" busted tests/

coverage:
	rm -f luacov.stats.out luacov.report.out
	LUA_PATH="packages/matrixbot/src/usr/lib/lua/?.lua;;" busted --coverage tests/
	luacov
	@sed -n '/^Summary/,$$p' luacov.report.out

verify: check test
