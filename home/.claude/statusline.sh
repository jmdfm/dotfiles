#!/usr/bin/env bash
# Claude Code status line. Reads the status JSON Claude Code sends on stdin;
# no network calls, no credentials, nothing written to disk.
#
#   Opus 5.5                | 84.3k / 200k (42% used) | 115.7k 58% free
#   current: ●●●●○○○○○○ 38% | weekly: ●●○○○○○○○○ 21%
#   resets 5:00pm (3h16m)   | resets Thu, 7:00pm
#   host                    | me@example.com          | ~/dir
#
# Columns line up across rows, each as wide as its widest cell. The limit
# rows appear only for subscription (or gateway spend-limit) sessions, after
# the first response.
email=$(jq -r '.oauthAccount.emailAddress // "no account"' ~/.claude.json 2>/dev/null) || email="no account"
host=$(hostname -s 2>/dev/null || cat /etc/hostname 2>/dev/null)

jq -rj --arg email "${email:-no account}" --arg host "$host" --arg home "$HOME" '
  def esc(rgb): "\u001b[38;2;\(rgb)m";
  def blue: esc("0;153;255");  def orange: esc("255;176;85"); def green: esc("0;160;0");
  def cyan: esc("46;149;153"); def red: esc("255;85;85");     def yellow: esc("230;200;0");
  def white: esc("220;220;220");
  def dim: "\u001b[2m"; def reset: "\u001b[0m";
  def sep: " \(dim)|\(reset) ";
  def rep(s; n): if n > 0 then [range(n)] | map(s) | join("") else "" end;

  # A table cell: plain text (for width) and the coloured text to print.
  def cell($plain; $colored): {p: $plain, c: $colored};
  def blank: cell(""; "");

  # Rows of cells -> lines, every column padded to its widest cell.
  def table:
    map(until(length == 0 or (last.p != ""); .[:-1]))       # drop trailing blank cells
    | map(select(length > 0)) as $rows
    | ([$rows[] | length] | max // 0) as $n
    | [range($n) as $i | [$rows[] | (.[$i] // blank).p | length] | max] as $w
    | $rows
    | map(. as $r | [range($r | length) as $i
          | $r[$i] | if $i < ($r | length) - 1 then .c + rep(" "; $w[$i] - (.p | length)) else .c end]
          | join(sep))
    | join("\n");

  # 84321 -> "84.3k", 200000 -> "200k", 1200000 -> "1.2m"
  def tok:
    if . >= 1000000 then "\((. / 100000 | round) / 10)m"
    elif . >= 1000 then "\((. / 100 | round) / 10)k"
    else "\(. | round)" end;

  # Ten-dot bar, coloured by how full it is: [plain, coloured]
  def bar:
    ([[., 0] | max, 100] | min) as $p
    | ($p / 10 | round) as $n
    | (if $p >= 90 then red elif $p >= 70 then yellow elif $p >= 50 then orange else green end) as $c
    | [rep("●"; $n) + rep("○"; 10 - $n), "\($c)\(rep("●"; $n))\(dim)\(rep("○"; 10 - $n))\(reset)"];

  # Local time from epoch seconds. localtime: [year, month, day, hour, min, sec, weekday, yearday]
  def clock: (.[3] % 12 | if . == 0 then 12 else . end) as $h
    | "\($h):\(.[4] | tostring | if length < 2 then "0" + . else . end)\(if .[3] >= 12 then "pm" else "am" end)";
  def left: ((. - now) / 60 | floor) as $m
    | if $m > 0 then " (\($m / 60 | floor)h\($m % 60)m)" else "" end;
  def soon: (localtime | clock) + left;                                        # 5:00pm (3h16m)
  def day: localtime | "\(["Sun","Mon","Tue","Wed","Thu","Fri","Sat"][.[6]]), \(clock)";  # Thu, 7:00pm

  # One limit column: {bar: cell, reset: cell}. Claude Code drops a window
  # while none is active (nothing used), so a missing one shows as 0%: a blank
  # first column would be eaten by Claude Code trimming leading spaces.
  def limit($name; when):
    if . == null then
      (0 | bar) as $b
      | {bar: cell("\($name): \($b[0]) 0%"; "\(white)\($name):\(reset) \($b[1]) \(green)0%\(reset)"),
         reset: cell("resets –"; "\(white)resets \(dim)–\(reset)")}
    else (.used_percentage | bar) as $b
      | (.used_percentage | round) as $pct
      | {bar: cell("\($name): \($b[0]) \($pct)%"; "\(white)\($name):\(reset) \($b[1]) \(green)\($pct)%\(reset)"),
         reset: cell("resets \(.resets_at | when)"; "\(white)resets \(.resets_at | when)\(reset)")}
    end;
  def spend:
    if . == null then {bar: blank, reset: blank}
    else (.used_percentage | bar) as $b
      | (if .used_usd then "$\(.used_usd * 100 | round / 100)/$\(.limit_usd)" else "\(.used_percentage | round)%" end) as $amt
      | {bar: cell("spend: \($b[0]) \($amt)"; "\(white)spend:\(reset) \($b[1]) \(cyan)\($amt)\(reset)"),
         reset: cell("resets \(.resets_at | day)"; "\(white)resets \(.resets_at | day)\(reset)")}
    end;

  (.model.display_name // "Claude") as $model
  | (.context_window // {}) as $cw
  | ($cw.context_window_size // 200000) as $size
  | ($cw.total_input_tokens // 0) as $used
  | ($cw.used_percentage // 0 | round) as $pct
  | ($cw.remaining_percentage // (100 - $pct) | round) as $free
  | (.rate_limits // {}) as $rl
  | ((if $rl.five_hour or $rl.seven_day then
        [($rl.five_hour | limit("current"; soon)), ($rl.seven_day | limit("weekly"; day))]
      else [] end)
     + [($rl.spend_limit | spend)]) as $lim
  | ((.workspace.current_dir // .cwd // "") as $d
      | if $d == $home then "~" elif ($d | startswith($home + "/")) then "~" + $d[($home | length):] else $d end
      # Deep paths keep their last two folders: ~/a/b/c/d -> …/c/d
      | split("/") | if length > 3 then "…/" + (.[-2:] | join("/")) else join("/") end) as $dir

  | [ [ cell($model; "\(blue)\($model)\(reset)"),
        cell("\($used | tok) / \($size | tok) (\($pct)% used)";
             "\(orange)\($used | tok) / \($size | tok)\(reset) \(green)(\($pct)% used)\(reset)"),
        cell("\([$size - $used, 0] | max | tok) \($free)% free";
             "\(orange)\([$size - $used, 0] | max | tok)\(reset) \(blue)\($free)% free\(reset)") ],
      ($lim | map(.bar)),
      ($lim | map(.reset)),
      [ cell($host; "\(dim)\($host)\(reset)"), cell($email; "\(dim)\($email)\(reset)"), cell($dir; "\(dim)\($dir)\(reset)") ]
    ] | table
' 2>/dev/null || printf 'Claude'
