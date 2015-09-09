PATH := ./node_modules/.bin:${PATH}
LSC_VER := $(shell lsc -v)

.PHONY : init clean build dist check-lsc publish

init:
	npm install

clean:
	rm -rf lib/ test/*.js node_modules

check-lsc:
	@ if [ "$(LSC_VER)" != "LiveScript 1.2.0" ] ; then \
		echo "LiveScript 1.2.0 required." ; \
		exit 1 ; \
	fi

build: check-lsc
	lsc -o lib/ -c src/

dist: clean init build

publish: dist
	npm publish
