require! {
  child_process
  fs
  ip
  async
}
global <<< require \prelude-ls

_namespaces         = {}
_test-url           = \https://icanhazip.com
_delete-all-retries = 5 # delete retries when calling NetNS.delete-all()
_delete-all-delay   = 2000ms # delay between NetNS.delete-all() retries

function NetNS ip-address
  @ip-address = ip-address
  @_long      = ip.to-long ip-address
  @name       = "ns#{@_long}"
  @_verified  = false
  if _namespaces[@name]
    return that # allow only single instances of namespaces
  _namespaces[@name] = @

NetNS.delete-all = (cb, retries=_delete-all-retries) ->
  pending = 0
  (ns) <- Obj.each _, _namespaces
  pending++
  ns.delete (-> pending--)
  timer = set-interval (->
    unless pending
      clear-interval timer
      existing = Obj.filter (._exists!), _namespaces
      if (keys existing).length
        if retries
          <- set-timeout _, _delete-all-delay
          NetNS.delete-all cb, retries - 1
        else
          error = new Error "failed to delete some namespaces"
          error.namespaces = existing
          cb error if cb
      else
        cb void if cb
  ), 100ms

NetNS.prototype.run = (command, cb, opts={ -verify }) ->
  (create-err) <~ @create
  if create-err
    (delete-err) <- @delete # delete ((potentially) partially-created) namespace
    if delete-err
      create-err.deletion-error = delete-err 
      cb create-err
  else
    run = ~>
      ns-wrap = "ip netns exec #{@name} #{command}".split ' '
      ns-proc = child_process.spawn ns-wrap.0, ns-wrap.slice(1), { stdio: \pipe }
      cb void, ns-proc
    if ! @_verified and opts.verify
      (test-err) <~ @test
      if test-err
        cb test-err
      else
        run!
    else
      run!

NetNS.prototype.create = (cb) ->
  (err, exists) <~ @_exists
  if err
    cb err
  else if exists in [ false, null ] # (re-)create if doesn't (or does partially) exist
    name-suffix  = @_long
    last2-octets = @ip-address.replace /^\d+\.\d+\./, ''
    async.series [
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
    ], ((cmd, cb) ->
      (err, stdout, stderr) <- child_process.exec cmd
      if err
        console.error 'NetNS.create error: ', cmd, stderr
        cb err 
      else
        cb void
    ), ((err) ->
      if err then cb err else cb void
    )
  else # if exists is true # assume it exists and return success
    cb void

NetNS.prototype.delete = (cb) ->
  (err, exists) <~ @_exists
  if err
    cb err
  else if exists in [ true, null ] # (re-)delete if does (or does partially) exist
    name-suffix  = @_long
    last2-octets = @ip-address.replace /^\d+\.\d+\./, ''
    async.series [ # execute all commands regardless of errors
      "ip netns del ns#{name-suffix}"
      "ip link del d#{name-suffix}"
      "iptables -t nat -D PREROUTING -d #{@ip-address} -j DNAT --to 10.#{last2-octets}.1"
      "iptables -t nat -D POSTROUTING -s 10.#{last2-octets}.0/31 -j SNAT --to #{@ip-address}"
    ], ((cmd, cb) ->
      (err, stdout, stderr) <- child_process.exec cmd
      if err
        console.error 'NetNS.delete error: ', cmd, stderr
        cb err 
      else
        cb void
    ), ((err) ->
      if err then cb err else cb void
    )
  else # if exists is false # assume it exists and return success
    cb void

NetNS.prototype._exists = (cb) -> # comprehensive existence check. result can be true, false, or null (partially exists)
  last2-octets = @ip-address.replace /^\d+\.\d+\./, ''

  pre-routing-exists = false
  post-routing-exists = false
  netns-exists = fs.exists-sync "/var/run/netns/#{@name}" # check for existence of namespace
  (err, stdout, stderr) <~ child_process.exec 'iptables -t nat -L -n'
  console.log stdout
  if err # unknown error so report back null to be safe
    console.error stderr
    return cb void, null
  else
    if stdout.index-of(@ip-address) isnt -1 and stdout.index-of("to:10.#last2-octets.1") isnt -1
      pre-routing-exists := true
    if stdout.index-of("10.#last2-octets.0/31") isnt -1 and stdout.index-of("to:#{@ip-address}") isnt -1
      post-routing-exists := true
    tests = [ netns-exists, pre-routing-exists, post-routing-exists ]
    console.log tests
    if all (is true), tests
      return cb void, true
    else if any (is true), tests
      return cb void, null
    else if all (is false), tests
      return cb void, false
    else # guard
      return cb void, null

NetNS.prototype.test = (cb) ->
  @_verified = false
  (err, exists) <~ @_exists
  if err
    cb err
  else if exists is true # (re-)delete if does (or does partially) exist
    cmd = "ip netns exec #{@name} curl -A www.npmjs.com/package/netns #{_test-url}"
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
        @_verified = true
        cb void
  else
    cb new Error "namespace doesn't seem to exist"

#process.once \beforeExit, NetNS.delete-all
#process.once \SIGINT, -> 
#  <- NetNS.delete-all
#  process.exit 130
#process.once \SIGTERM, -> 
#  <- NetNS.delete-all
#  process.exit 143

module.exports = NetNS
