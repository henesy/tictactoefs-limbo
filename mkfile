</mkconfig

DISBIN = /dis

TARG=\
	tttfs.dis

</mkfiles/mkdis

demo:V: all
	dir = /n/t
	mount {tttfs} $dir
	echo x 0 0 > $dir/ctl
	cat $dir/board
	echo o 1 1 > $dir/ctl
	cat $dir/board
	echo x 1 0 > $dir/ctl
	cat $dir/board
	echo o 0 2 > $dir/ctl
	cat $dir/board
	echo x 0 1 > $dir/ctl
	cat $dir/board
	echo o 2 0 > $dir/ctl
	cat $dir/board
	cat $dir/score
	echo -n 'Game: '; cat $dir/no

