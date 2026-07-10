.PHONY: build run test clean

build:
	dune build

run:
	dune exec bin/main.exe

test:
	dune runtest

# Open the OCaml REPL with your library loaded
repl:
	dune utop lib

clean:
	dune clean
