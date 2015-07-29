PATH := ./node_modules/.bin:${PATH}

.PHONY : init clean build dist publish

init:
	npm install

clean: clean-docs
	rm -rf lib/ test/*.js

build:
	lsc -o lib/ -c src/

dist: clean init docs build

publish: dist
	npm publish
