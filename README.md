NetNS
=====

Network namespace management for Linux.

## Installation

  npm install netns

## Usage

```
require! {
  netns
}

ns = new netns \4.3.2.10

# create namespace
(err) <- ns.create
if err
  console.error "error creating namespace", JSON.stringify(err, null, 2)
else
  console.log "#{ns.name} created w/ address #{ns.ip-address}"

# use your namespace
# sudo ip netns exec curl icanhazip.com
# ...

# test namespace
(err) <- ns.test
if err
  console.error "error testing namespace", JSON.stringify(err, null, 2)
else
  console.log "namespace test OK"

# delete namespace
(err) <- ns.delete
if err
  console.error "error deleting namespace", JSON.stringify(err, null, 2)
else
  console.log "namespace deleted"
```

## Contributing

Please edit the LiveScript under the *src* dir. Run `make build` and commit the *src* and *lib* dirs.

## Special thanks

To James Loosli <james@instantchannelinc.com> for authoring the shell script on which this library is based.

## Release History

* 1.1.2 Adds delete-all

* 1.0.0 Initial release
