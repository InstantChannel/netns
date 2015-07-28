require! {
  child_process
  fs
}
global <<< require \prelude-ls

_namespaces         = {}
_test-url           = \https://icanhazip.com
_delete-all-retries = 5 # delete retries when calling NetNS.delete-all()
_delete-all-delay   = 2000ms # delay between NetNS.delete-all() retries

function NetNS ip-address
  @ip-address = ip-address
  @name       = "ns#{ip-address.replace /\./g, \-}"
  if _namespaces[@name]
    return that # allow only single instances of namespaces
  _namespaces[@name] = @

NetNS.delete-all = (cb) ->
  pending = 0
  (ns) <- Obj.each _, _namespaces
  pending++
  ns.delete (-> pending--)
  timer = set-interval (->
    if pending <= 0
      clear-interval timer
      cb void
  ), 100ms

NetNS.prototype.create = (cb) ->
  unless @_exists!
    name-suffix  = @ip-address.replace /\./g, \-
    last2-octets = @ip-address.replace /^\d+\.\d+\./, ''
    _exec-series [
      "ip netns add ns#{name-suffix}" # create ns
      "ip netns exec ns#{name-suffix} ip link set lo up"

      "ip link add d#{name-suffix} type veth peer name v#{name-suffix}" # create d and v
      "ip link set up d#{name-suffix}"

      "ip link set v#{name-suffix} netns ns#{name-suffix}" # add v to ns
      "ip netns exec ns#{name-suffix} ip link set v#{name-suffix} up"

      "ip addr add 10.#{last2-octets}.0/31 dev d#{name-suffix}" # add IP addresses to d and v
      "ip netns exec ns#{name-suffix} ip addr add 10.#{last2-octets}.1/31 dev v#{name-suffix}"

      "ip netns exec ns#{name-suffix} ip route add default via 10.#{last2-octets}.0" # set up route in ns

      "iptables -t nat -A PREROUTING -d #{@ip-address} -j DNAT --to 10.#{last2-octets}.1"
      "iptables -t nat -A POSTROUTING -s 10.#{last2-octets}.0/31 -j SNAT --to #{@ip-address}"
    ], cb
  else # assume it exists and return success
    cb void

NetNS.prototype.delete = (cb) ->
  if @_exists!
    name-suffix  = @ip-address.replace /\./g, \-
    last2-octets = @ip-address.replace /^\d+\.\d+\./, ''
    _exec-series [
      "ip netns del ns#{name-suffix}"
      "ip link del d#{name-suffix}"
      "iptables -t nat -D PREROUTING -d #{@ip-address} -j DNAT --to 10.#{last2-octets}.1"
      "iptables -t nat -D POSTROUTING -s 10.#{last2-octets}.0/31 -j SNAT --to #{@ip-address}"
    ], cb
  else # assume it doesn't exist and return success
    cb void

NetNS.prototype._exists = ->
  fs.exists-sync "/var/run/netns/#{@name}" # check for existence of namespace

NetNS.prototype.test = (cb) ->
  if @_exists!
    cmd = "ip netns exec #{@name} curl #{_test-url}"
    data-buf = err-buf = ''
    proc = child_process.exec cmd
    proc
      ..stdout.on \data, (-> data-buf += it)
      ..stderr.on \data, (-> err-buf += it)
    proc.on \close, (code) ~>
      if code is not 0
        cb new Error err-buf
      else if data-buf is not "#{@ip-address}\n"
        cb new Error "IP mismatch: got: #data-buf but expected: #{@ip-address}\\n"
      else
        cb void
  else
    cb new Error "namespace doesn't seem to exist"

# see: https://gist.github.com/millermedeiros/4724047
# spawn a child process and execute shell command
# borrowed from https://github.com/mout/mout/ build script
# author Miller Medeiros
# released under MIT License
# version: 0.1.0 (2013/02/01)

# execute a single shell command where "cmd" is a string
function _exec cmd, cb
  parts = cmd.split /\s+/g
  p = child_process.spawn parts.0, parts.slice(1), {stdio: \inherit}
  p.on \exit, (code) ->
    var err
    if code
      err = new Error "command #cmd exited with wrong status code #code"
      err.code = code
      err.cmd  = cmd
    if cb then cb err else cb void

# execute multiple commands in series
# this could be replaced by any flow control lib
function _exec-series cmds, cb
  exec-next = ->
    _exec cmds.shift!, (err) ->
      if err
        cb err
      else
        if cmds.length then exec-next! else cb void
  exec-next!

module.exports = NetNS
