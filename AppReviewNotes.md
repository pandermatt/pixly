# Pixly — Notes for App Review

Paste into **App Store Connect → App Review Information → Notes**.

---

Pixly is an arcade game (one pixel flying through an endless tunnel) presented in the style of a text
terminal, as a homage to the C console game the developers wrote as students.

**It is not a terminal.** Nothing is compiled, downloaded, installed or executed:
- The "start" button and `start` command only play a scripted animation of a build command, then start
  the built-in game. The C and Swift "source files" are bundled text shown with `cat`.
- The shell understands a fixed list of built-in commands (below); anything else answers "command not found".
- The welcome screen on first launch says "It's a game, not a terminal".

**How to play:** tap the screen (iPhone/iPad), press space (Mac), click the Siri Remote (Apple TV) or tap
the watch face / turn the Digital Crown (Apple Watch) to jump. Game controllers are supported (A jumps).
Pixly 2.0 (the "2.0" button) is a modern version with smooth physics.

**Game Center:** two leaderboards (classic and Pixly 2.0) and 15 achievements. Scores are the Game Center
alias; nothing else is collected.

**Commands shown in `help`:** start, start2, settings, highscore, highscore2, leaderboard, welcome.

**Additional commands and easter eggs (not listed in the app, all harmless):**
- `theme`, `icon`, `avatar`, `scanlines`: change settings (also available in the game's Settings menu).
- `./pixly`, `./pixly2`: start a game without the build animation. `clear`, `credits`, `whoami`, `echo`.
- `ls`, `cat FILE`: list and show the bundled text files (C sources, `credits.txt`, `Pixly2.swift` with a
  link to the open-source code on GitHub, the local highscore tables, the settings as `.pixlyrc`).
- `rm FILE`: "removes" a bundled file inside the game only. Removing a C file makes the next build fail
  with a message; the "restore files" button (or `git checkout -- .`) brings it back. Removing a highscore
  file clears that local table; removing `.pixlyrc` resets the settings.
- `neofetch` (game info), `git` / `git status` / `git log` / `git blame` / `git push --force` (jokes),
  `top`, `ping`, `coffee` / `brew coffee` ("418 I'm a teapot"), `sudo`, `exit`: one-line jokes.
- `open`, `xed`, `xcodebuild`: show a link to the project on GitHub.

**Apple TV:** no text input; the menu and games are fully controlled with the Siri Remote.
**Apple Watch:** only the classic game; it starts directly and can run without the iPhone.

---

Metadata reminder: lead the App Store description and screenshots with gameplay, and describe it as a
game in a retro terminal style.
