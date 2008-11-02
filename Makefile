# Vocabulink CGI

FCGI = vocabulink.fcgi

all : $(FCGI)

vocabulink.fcgi : Vocabulink.lhs Vocabulink/*.lhs
	ghc -Wall -fglasgow-exts -threaded -package fastcgi --make -o $(FCGI) $^

install :
	install -o root -g root $(FCGI) /usr/local/bin
	-killall $(FCGI)
	spawn-fcgi -f "/usr/local/bin/$(FCGI) 2>> /tmp/vocabulink.error.log" -p 10033 -u lighttpd -g lighttpd

clean:
	rm *.o *.hi Vocabulink/*.o Vocabulink/*.hi

test :
	ghci -fglasgow-exts Vocabulink.lhs

sloc : Vocabulink.lhs Vocabulink/*.lhs
	echo $^ | xargs -n 1 lhs2TeX --code | wc --lines
