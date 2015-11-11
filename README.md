# lang-try-ruby-proxy
Ruby programming languge try: caching web proxy server

# Usage
## Arguments:

* port (default=8992)
* cached? (default=true)
* verbose? (default=true)

`$ruby proxy.rb 8992 true true`

## Notes:

1. Cache settings currently: ~1MB per item max, ~5Mb max total;
2. Tested for both clang and jvm rubies;
3. Mostly tested in Chrome (as the task mentiones); other browsers may not behave as expected;
4. Dynamic pages (asp, jsp,...) are NOT cached;
5. For better cache capabilities demonstration it sometimes makes sense to clear the browser cache;
