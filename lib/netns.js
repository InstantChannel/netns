(function(){
  var child_process, fs, _namespaces, _testUrl, _deleteAllRetries, _deleteAllDelay;
  child_process = require('child_process');
  fs = require('fs');
  import$(global, require('prelude-ls'));
  _namespaces = {};
  _testUrl = 'https://icanhazip.com';
  _deleteAllRetries = 5;
  _deleteAllDelay = 2000;
  function NetNS(ipAddress){
    var that;
    this.ipAddress = ipAddress;
    this.name = "ns" + ipAddress.replace(/\./g, '-');
    this._verified = false;
    if (that = _namespaces[this.name]) {
      return that;
    }
    return _namespaces[this.name] = this;
  }
  NetNS.deleteAll = function(cb, retries){
    var pending;
    retries == null && (retries = _deleteAllRetries);
    pending = 0;
    return Obj.each(function(ns){
      var timer;
      pending++;
      ns['delete'](function(){
        return pending--;
      });
      return timer = setInterval(function(){
        var existing, error;
        if (!pending) {
          clearInterval(timer);
          existing = Obj.filter(function(it){
            return it._exists();
          }, _namespaces);
          if (keys(existing).length) {
            if (retries) {
              return setTimeout(function(){
                return NetNS.deleteAll(cb, retries - 1);
              }, _deleteAllDelay);
            } else {
              error = new Error("failed to delete some namespaces");
              error.namespaces = existing;
              return cb(error);
            }
          } else {
            return cb(void 8);
          }
        }
      }, 100);
    }, _namespaces);
  };
  NetNS.prototype.run = function(command, cb, opts){
    var this$ = this;
    opts == null && (opts = {
      verify: false,
      persist: false
    });
    return this.create(function(createErr){
      var run;
      if (createErr) {
        return this$['delete'](function(deleteErr){
          if (deleteErr) {
            createErr.deletionError = deleteErr;
            return cb(createErr);
          }
        });
      } else {
        run = function(){
          var nsWrap, x$, nsProc;
          nsWrap = ("ip netns exec " + this$.name + " " + command).split(' ');
          x$ = nsProc = child_process.spawn(nsWrap[0], nsWrap.slice(1), {
            stdio: 'inherit'
          });
          x$.on('close', function(){
            if (!opts.persist) {
              return setTimeout(function(){
                return this$['delete'](function(deleteErr){});
              }, 500);
            }
          });
          return cb(void 8, nsProc);
        };
        if (!this$._verified && opts.verify) {
          return this$.test(function(testErr){
            if (testErr) {
              return cb(testErr);
            } else {
              return run();
            }
          });
        } else {
          return run();
        }
      }
    });
  };
  NetNS.prototype.create = function(cb){
    var nameSuffix, last2Octets;
    if (!this._exists()) {
      nameSuffix = this.ipAddress.replace(/\./g, '-');
      last2Octets = this.ipAddress.replace(/^\d+\.\d+\./, '');
      return _execSeries(["ip netns add ns" + nameSuffix, "ip netns exec ns" + nameSuffix + " ip link set lo up", "ip link add d" + nameSuffix + " type veth peer name v" + nameSuffix, "ip link set up d" + nameSuffix, "ip link set v" + nameSuffix + " netns ns" + nameSuffix, "ip netns exec ns" + nameSuffix + " ip link set v" + nameSuffix + " up", "ip addr add 10." + last2Octets + ".0/31 dev d" + nameSuffix, "ip netns exec ns" + nameSuffix + " ip addr add 10." + last2Octets + ".1/31 dev v" + nameSuffix, "ip netns exec ns" + nameSuffix + " ip route add default via 10." + last2Octets + ".0", "iptables -t nat -A PREROUTING -d " + this.ipAddress + " -j DNAT --to 10." + last2Octets + ".1", "iptables -t nat -A POSTROUTING -s 10." + last2Octets + ".0/31 -j SNAT --to " + this.ipAddress], cb);
    } else {
      return cb(void 8);
    }
  };
  NetNS.prototype['delete'] = function(cb){
    var nameSuffix, last2Octets;
    if (this._exists()) {
      nameSuffix = this.ipAddress.replace(/\./g, '-');
      last2Octets = this.ipAddress.replace(/^\d+\.\d+\./, '');
      return _execSeries(["ip netns del ns" + nameSuffix, "ip link del d" + nameSuffix, "iptables -t nat -D PREROUTING -d " + this.ipAddress + " -j DNAT --to 10." + last2Octets + ".1", "iptables -t nat -D POSTROUTING -s 10." + last2Octets + ".0/31 -j SNAT --to " + this.ipAddress], cb);
    } else {
      return cb(void 8);
    }
  };
  NetNS.prototype._exists = function(){
    return fs.existsSync("/var/run/netns/" + this.name);
  };
  NetNS.prototype.test = function(cb){
    var cmd, dataBuf, errBuf, proc, x$, this$ = this;
    this._verified = false;
    if (this._exists()) {
      cmd = "ip netns exec " + this.name + " curl -A www.npmjs.com/package/netns " + _testUrl;
      dataBuf = errBuf = '';
      proc = child_process.exec(cmd);
      x$ = proc;
      x$.stdout.on('data', function(it){
        return dataBuf += it;
      });
      x$.stderr.on('data', function(it){
        return errBuf += it;
      });
      return proc.on('close', function(code){
        if (code !== 0) {
          return cb(new Error(errBuf));
        } else if (dataBuf !== this$.ipAddress + "\n") {
          return cb(new Error("IP mismatch: got: " + dataBuf + " but expected: " + this$.ipAddress + "\\n"));
        } else {
          this$._verified = true;
          return cb(void 8);
        }
      });
    } else {
      return cb(new Error("namespace doesn't seem to exist"));
    }
  };
  function _exec(cmd, cb){
    var parts, p;
    parts = cmd.split(/\s+/g);
    p = child_process.spawn(parts[0], parts.slice(1), {
      stdio: 'ignore'
    });
    return p.on('exit', function(code){
      var err;
      if (code) {
        err = new Error("command " + cmd + " exited with wrong status code " + code);
        err.code = code;
        err.cmd = cmd;
      }
      if (cb) {
        return cb(err);
      } else {
        return cb(void 8);
      }
    });
  }
  function _execSeries(cmds, cb){
    var execNext;
    execNext = function(){
      return _exec(cmds.shift(), function(err){
        if (err) {
          return cb(err);
        } else {
          if (cmds.length) {
            return execNext();
          } else {
            return cb(void 8);
          }
        }
      });
    };
    return execNext();
  }
  module.exports = NetNS;
  function import$(obj, src){
    var own = {}.hasOwnProperty;
    for (var key in src) if (own.call(src, key)) obj[key] = src[key];
    return obj;
  }
}).call(this);
