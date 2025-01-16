## SIRProxy - the Server Initiated Reverse Proxy

### Why this?

In some cases it is impossible for
both server and proxy have open ports.

This implementation solves the issue by requiring only
the proxy to open ports, and using a local rerouter
on the server side to connect to the proxy and route the
connections to the server

### Installation

The requirements to run are `Perl version 5.0+`

All executables here need to be combined with the `locale.pl` file first to create standalone files.  
To do this run:

> 1. `cat locale.pl 'part name' > 'file name'`
> 2. `chmod 755 'file name'`

After that you may put the resulting file to `$PATH`, or call it by its full name

### Usage

> #### To start the UDP proxy
>
> 1. Start the server
> 2. On the proxy side do `udp_multiplex.pl <server port> <client port>`
> 3. On the server side do `udp_demultiplex.pl <server host> <server port> <proxy host> <proxy port>`

> #### To start the TCP proxy
>
> 1. Start the server
> 2. On the proxy side do `tcp_multiplex.pl <server metaport> <server dataport> <client port>`
> 3. On the server side do `tcp_demultiplex.pl <server host> <server port> <proxy host> <proxy metaport> <proxy dataport>`

For advanced options see `<command> -h`

### Contribution

To contribute open an issue or a pull request on GitHub. All contributions are welcome
