# Online server list

`servers.json` tells the game where the official lobby server is. The Internet Lobby
screen downloads it from GitHub (`main` branch) when it opens and fills in the first
`url`, so moving the server only needs a change here, not a game update. Players who
typed their own address keep it.

The game also has the address built in (`DEFAULT_SERVER` in `scripts/ui/server_lobby.gd`)
for when GitHub can't be reached; update it as well with the next release.
