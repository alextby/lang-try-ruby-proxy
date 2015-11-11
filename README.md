# lang-try-ruby-proxy
Ruby programming languge try: caching web proxy server

Usage
====== Arguments:

[0] - port (default=8992)
[1] - cached? (default=true)
[2] - verbose? (default=true)

====== Usage:

$ruby proxy.rb 8992 true true
=====================================
 | Arguments:
 |----- port=8992
 |----- cached=true
 |----- verbose=true
=====================================
thread_d: [PROXY]: Started
...

====== Hints:

1). Cache settings currently: ~1MB per item max, ~5Mb max total;
2). Tested with Rubies: ruby-1.9.2-p320, jruby 1.7.3;
3). Mostly tested with Chrome (as the task mentiones); other browsers may not behave as expected;
4). Dynamic pages (asp, jsp,...) are NOT cached
5). For better cache capabilities demonstration it sometimes makes sense to clear the browser cache;
6). oracle.com gives reasonably good cache load and nice cache hits;
