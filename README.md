## SIRProxy - the Server Initiated Reverse Proxy

> # **DO NOT USE THIS BRANCH** 
>
> The "UDP" protocol proxy in Bash implementation
> doesn't work great with high load.  
> Use the Perl implementation instead

### Why this?

In some cases it is impossible to have
both server and proxy have open ports.  

This implementation solves it by only requiring
the proxy to open ports, and using a local rerouter
on the server side, which connects to the proxy, and routes the
connections to the server

### How to use this?

The requirements to run are `Bash >4.0` and `socat`

All executables here need to be combined with the `locale` file first to be standalone  
To do this use `cat locale 'part name' > 'file name'`, then run `chmod 755 'file name'`  
After that you may put the resulting file to `$PATH`, or call it by its full name

> #### To start the UDP proxy
>
> 1. Start the server
> 2. On the proxy side do `udp_multiplex <server port> <client port>`
> 3. On the server side do `udp_demultiplex <server host> <server port> <proxy host> <proxy port>`

> #### To start the TCP proxy
>
> 1. Start the server
> 2. On the proxy side do `tcp_multiplex <server metaport> <server dataport> <client port>`
> 3. On the server side do `tcp_demultiplex <server host> <server port> <proxy host> <proxy metaport> <proxy dataport>`

For advanced options see `<command> -h`
