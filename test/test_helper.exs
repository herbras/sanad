# Live-provider tests need the real CLIs installed and real credentials, so
# they are opt-in: `mix test --include live_providers`, or SANAD_LIVE=1.
live? = System.get_env("SANAD_LIVE") == "1"

ExUnit.start(exclude: if(live?, do: [], else: [:live_providers]))
