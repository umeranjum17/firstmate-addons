# kill-guard

Blocks kill, pkill and killall aimed at PID 1, the systemd user manager, the herdr server, or any process the caller did not start. A block is final.

## Known gaps

- Command words that are not literal names are not judged: `$k -9 1`, `f(){ kill 1; }; f`, `find / -exec kill {} \;`, `eval "$x"`.
- A `<<WORD` inside quotes or a comment opens a heredoc that hides the following lines until a line equal to WORD.
- Wrapper options that take an argument hide the command: `sudo -u root kill 1`, `timeout -s KILL 5 kill 1`.
