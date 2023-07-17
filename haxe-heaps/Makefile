CFLAGS = -Iout -lhl -luv
CFLAGS += -I/usr/local/include -I/usr/local/homebrew/include -I/usr/local/homebrew/Cellar/hashlink/1.13/libexec/include
LIBFLAGS = -L/usr/local/lib -L/usr/local/homebrew/lib -L/usr/local/homebrew/Cellar/hashlink/1.13/libexec/lib

out/main: out/main.c
	clang++ -std=c++11 -arch x86_64 $(CFLAGS) -o out/main $(LIBFLAGS) out/main.c
