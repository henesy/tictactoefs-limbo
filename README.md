# Tic-Tac-Toe FS

## Requirements

This filesystem is written in the Limbo programming language for the Inferno operating system. 

The [purgatorio](https://code.9front.org/hg/purgatorio)  fork of Inferno is recommended. 

No other dependencies are required if Inferno is installed. 

## Building

	mk

## Demo

	mk demo

## Usage

### Arguments

	usage: tttfs [-Dr] [-u user] [-w width]

`-D` enables debug logging and tracing via styx(2). 

`-r` sets raw mode to on by default. 

`-u` sets `user` as the owner of the fs tree. 

`-w` sets the `width` of the game board, which is a square. 

### Command format

Commands are written to the `/ctl` file in the fs. 

#### Moves

	x|o X Y

`x` or `o` is exclusive and indicates whether to place an `x` piece or an `o` piece. 

`X` indicates the X-coordinate on the board.

`Y` indicates the Y-coordinate on the board. 

#### Auxiliary 

	new

Starts a new game, keeping score if the current game has ended naturally. 

	rawon

Sets the board to raw mode, that is, the printing will not include the visual grid as to allow easier automated parsing. 

	rawoff

Unsets the raw mode for the board. Non-raw mode is the default behavior of the board file. 

### Filesystem structure

`/ctl`		-- command input, or, control, file

`/board`	-- the current board state

`/no`		-- current game number, the first game is 1

`/score`	-- current game score

## Examples

If you're used to how Plan 9 provides file servers as per postmountsrv(2) and friends, the operation of Inferno file servers may be unintuitive. 

In Inferno, a styx(2) file server listens on stdin and if run from the shell directly, will seem to just hang. There are several approaches to making the server accessible, in this case, we use mount(1) to place our file server in an intuitive location. 

From inside Inferno:

	; mount {mntgen} /n	# Not necessary under purgatorio
	; mount {tttfs} /n/ttt
	; lc /n/ttt
	board	ctl		no		score
	; cat /n/ttt/board
	 │ │ 
	─────
	 │ │ 
	─────
	 │ │ 
	; echo x 0 0 > /n/ttt/ctl
	; cat /n/ttt/board
	x│ │ 
	─────
	 │ │ 
	─────
	 │ │ 
	; echo o 1 1 > /n/ttt/ctl
	; cat /n/ttt/board
	x│ │ 
	─────
	 │o│ 
	─────
	 │ │ 
	; 

To host the service over the network and use from plan9port:

	; mount {mntgen} /n	# Not necessary under purgatorio
	; mount {ttfs} /n/ttt
	; listen -A 'tcp!*!1337' { export /n/ttt & }
	
	$ 9p -a 'tcp!localhost!1337' read board
	 │ │ 
	─────
	 │ │ 
	─────
	 │ │ 
	$ echo x 0 0 | 9p -a 'tcp!localhost!1337' write
	$ 9p -a 'tcp!localhost!1337' read board
	x│ │ 
	─────
	 │ │ 
	─────
	 │ │ 

You could also easily connect to the server from Linux, etc. with:

- 9pfuse
- 9mount
- mount
- wmiir

