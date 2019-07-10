implement TicTacToeFS;

include "sys.m";
	sys: Sys;
	sprint, print, fildes: import sys;
	OTRUNC, ORCLOSE, OREAD, OWRITE: import Sys;

include "draw.m";

include "arg.m";

include "styx.m";
	styx: Styx;
	Tmsg, Rmsg: import Styx;

include "styxservers.m";
	styxservers: Styxservers;
	Styxserver, Fid, Navigator,
	Navop, Enotfound, Enotdir: import styxservers;

include "string.m";
	strings: String;

TicTacToeFS: module {
	init: fn(nil: ref Draw->Context, argv: list of string);
};

# Represents a TTT game
Game: adt {
	board: array of array of int;
	size: int;
	xscore: int;	# X's number of won games
	oscore: int;	# O's ^
	no: int;		# Game number (starts at 1)
	over: int;
	check: fn(g: self ref Game);
	stringify: fn(g: self ref Game): string;
	init: fn(g: self ref Game, width: int);
	reset: fn(g: self ref Game);
};

# FS file index
Qroot, Qctl, Qboard, Qscore, Qno, Qmax: con iota;
tab := array[] of {
	(Qroot, ".", Sys->DMDIR|8r555),
	(Qctl, "ctl", 8r222),
	(Qboard, "board", 8r444),
	(Qscore, "score", 8r444),
	(Qno, "no", 8r444),
};

user: string	= "none";		# User owning the fs
chatty: int		= 0;			# Debug log toggle -- triggers styx(2) tracing
game: ref Game;			# Current game
raw: int		= 0;			# Raw mode t/f
turn: int		= 'x';			# Current turn -- starts at x

# Serves tic-tac-toe as a filesystem
init(nil: ref Draw->Context, argv: list of string) {
	sys = load Sys Sys->PATH;
	arg := load Arg Arg->PATH;
	if(arg == nil)
		raise "could not load arg";
	styx = load Styx Styx->PATH;
	if(styx == nil)
		raise "could not load styx";
	styxservers = load Styxservers Styxservers->PATH;
	if(styxservers == nil)
		raise "could not load styxservers";
	strings = load String String->PATH;
	if(strings == nil)
		raise "could not load strings";

	chatty = 0;
	width := 3;		# Default 3x3 board

	# Ref required to use methods properly
	# See: https://github.com/henesy/limbobyexample/blob/master/ADTs/adts.b
	g: Game;
	game = ref g;

	arg->init(argv);
	arg->setusage("tttfs [-Dr] [-u user] [-w width]");

	while((c := arg->opt()) != 0)
		case c {
		'D' =>
			chatty++;

		'u' =>
			user = arg->earg();

		'w' =>
			width = int arg->earg();
			if(width < 3)
				raise "width must be ≥ 3";
		'r' =>
			raw = 1;

		* =>
			arg->usage();
		}

	argv = arg->argv();

	user = readfile("/dev/user");
	if(user == nil)
		user = "none";

	# Initialize the game
	game.init(width);

	# Start 9p infrastructure
	styx->init();
	styxservers->init(styx);
	styxservers->traceset(chatty);
	
	# Start FS navigator on /
	navch := chan of ref Navop;
	spawn navigator(navch);

	nav := Navigator.new(navch);
	(tc, srv) := Styxserver.new(fildes(0), nav, big Qroot);

	# Primary server loop
	loop:
	while((tmsg := <-tc) != nil) {
		#sys->fprint(sys->fildes(2), "%s\n", tmsg.text());

		# Switch on operations being performed on a given Fid
		pick msg := tmsg {
		Open =>
			# Nothing of our stuff cares about getting opened
			# We respond with the default as such
			srv.default(msg);

		Read =>
			fid := srv.getfid(msg.fid);

			if(fid.qtype & Sys->QTDIR) {
				# This is a directory read
				srv.default(msg);
				continue loop;
			}

			case int fid.path {
			Qboard =>
				srv.reply(styxservers->readstr(msg, game.stringify()));

			Qno =>
				srv.reply(styxservers->readstr(msg, string game.no + "\n"));

			Qscore =>
				srv.reply(styxservers->readstr(msg, 
					sprint("X: %d\nO: %d\n", game.xscore, game.oscore)
				));

			* =>
				srv.default(msg);
			}

		Write =>
			fid := srv.getfid(msg.fid);

			case int fid.path {
			Qctl =>
				# Don't care about offset, we use small messages
				cmd := string msg.data;

				# Strip a trailing newline, if any; this is good for echo(1)
				(cmd, nil) = strings->splitl(cmd, "\n");

				reply: ref Rmsg = ref Rmsg.Write(msg.tag, len msg.data);

				case cmd {
				"new" =>
					game.reset();

				"rawon" =>
					raw = 1;

				"rawoff" =>
					raw = 0;

				* =>
					# Moves are passed on to validate
					err := move(cmd);
					if(err != nil)
						reply = ref Rmsg.Error(msg.tag, err);
				}
				srv.reply(reply);
				
			* =>
				srv.default(msg);
			}

		* =>
			srv.default(msg);
		}
	}

	exit;
}

# Processes if a move is valid or not
# Form is: x|o X Y
# Ex.: x 2 1
move(s: string): string {
	if(game.over)
		return "game is over";

	s = strings->tolower(s);
	(n, parts) := sys->tokenize(s, " \t");

	if(chatty)
		print("INFO ­ nparts: %d ;; str: %s\n", n, s);

	if(!(n >= 3))
		return "not enough arguments";

	piece := int (hd parts)[0];
	x := int hd tl parts;
	y := int hd tl tl parts;

	if(piece != turn)
		return "invalid move, it's currently " + sprint("%c", turn) + "'s turn";

	if(!('x' == piece || 'o' == piece))
		return "need 'x' or 'o' character for piece";

	if(x < 0 || x >= game.size)
		return "x out of bounds";

	if(y < 0 || y >= game.size)
		return "y out of bounds";

	if(game.board[y][x] != 0)
		return "there is already a piece there";

	game.board[y][x] = piece;

	# Toggle the turn
	case piece {
	'x' => turn = 'o';
	'o' => turn = 'x';
	}

	game.check();

	return nil;
}

# Initializes the game board and state -- called at start of each game
Game.reset(g: self ref Game) {
	g.over = 0;
	turn = 'x';
	
	g.board = array[g.size] of array of int;
	for(i := 0; i < len g.board; i++)
		g.board[i] = array[g.size] of { * => int 0};

	g.no++;
}

# Initializes the game for the first time -- called only once
Game.init(g: self ref Game, width: int) {
	g.oscore = g.xscore = g.no = 0;
	g.size = width;

	g.reset();
}

# Navigator function for moving around under /
navigator(c: chan of ref Navop) {
	loop: 
	for(;;) {
		navop := <-c;
		pick op := navop {
		Stat =>
			op.reply <-= (dir(int op.path), nil);
			
		Walk =>
			if(op.name == "..") {
				op.reply <-= (dir(Qroot), nil);
				continue loop;
			}

			case int op.path&16rff {

			Qroot =>
				for(i := 1; i < Qmax; i++)
					if(tab[i].t1 == op.name) {
						op.reply <-= (dir(i), nil);
						continue loop;
					}

				op.reply <-= (nil, Enotfound);
			* =>
				op.reply <-= (nil, Enotdir);
			}
			
		Readdir =>
			for(i := 0; i < op.count && i + op.offset < (len tab) - 1; i++)
				op.reply <-= (dir(Qroot+1+i+op.offset), nil);

			op.reply <-= (nil, nil);
		}
	}
}

# Given a path inside the table, this returns a Sys->Dir representing that path.
dir(path: int): ref Sys->Dir {
	(nil, name, perm) := tab[path&16rff];

	d := ref sys->zerodir;

	d.name	= name;
	d.uid		= d.gid = user;
	d.qid.path	= big path;

	if(perm & Sys->DMDIR)
		d.qid.qtype = Sys->QTDIR;
	else
		d.qid.qtype = Sys->QTFILE;

	d.mtime = d.atime = 0;
	d.mode = perm;

	#if(path == Qhello)
	#	d.length = big len greeting;

	return d;
}

# Reads a file into a string
readfile(f: string): string {
	fd := sys->open(f, Sys->OREAD);
	if(fd == nil)
		return nil;

	buf := array[Sys->ATOMICIO] of byte;
	s := "";

	while((n := sys->read(fd, buf, len buf)) > 0)
		s += string buf[0:n];

	return s;
}

# Outputs the game board as a string
Game.stringify(g: self ref Game): string {
	s := "";

	for(i := 0; i < len g.board; i++) {
		for(j := 0; j < len g.board; j++) {
			case g.board[i][j] {
			0 =>
				s += " ";
			* =>
				s += sprint("%c", g.board[i][j]);
			}
			
			if(!raw)
				# Place one less | than there are slots
				if(j < len g.board-1)
					s += "│";
		}

		if(!raw)
			# Place one less - than there are slots
			if(i < len g.board-1) {
				s += "\n";
				# Draw horizontal lines
				for(k := 0; k < 2*g.size-1; k++)
					s += "─";
			}
		s += "\n";
	}

	return s;
}

# Validate game state and lock if game is over -- O(n⁲)+ or so
Game.check(g: self ref Game) {
	i, j, c: int = 0;

	# Check vertical origins
	for(i = 0; i < g.size; i++) {
		c = g.board[i][0]; 
		for(j = 1; j < g.size && c != 0; j++)
			if(g.board[i][j] != c)
				break;

		if(j >= g.size) {
			case c {
			'x' => g.xscore++;
			'o' => g.oscore++;
			}
			g.over = 1;

			break;
		}
	}

	# Check horizontal origins
	for(j = 0; j < g.size; j++) {
		c = g.board[0][j]; 
		for(i = 1; i < g.size && c != 0; i++)
			if(g.board[i][j] != c)
				break;

		if(i >= g.size) {
			case c {
			'x' => g.xscore++;
			'o' => g.oscore++;
			}
			g.over = 1;

			break;
		}
	}
		

	# Check diagonal from 0,0
	i = 1;
	j = 1;
	c = g.board[0][0];
	for(; i < g.size && j < g.size && c != 0;) {
		if(g.board[i][j] != c)
			break;

		i++;
		j++;
	}

	if(j >= g.size) {
		case c {
		'x' => g.xscore++;
		'o' => g.oscore++;
		}
		g.over = 1;
	}

	# Check diagonal from top right
	i = 1;
	j = g.size-2;
	c = g.board[0][g.size-1];
	for(; i < g.size && j >= 0 && c != 0;) {
		if(g.board[i][j] != c)
			break;

		i++;
		j--;
	}

	if(i >= g.size) {
		case c {
		'x' => g.xscore++;
		'o' => g.oscore++;
		}
		g.over = 1;
	}

	if(chatty)
		print("INFO ­ game.over: %d\n", g.over);
}

