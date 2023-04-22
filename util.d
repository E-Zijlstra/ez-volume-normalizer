module util;

import std.conv;

string tos(T)(T t) { return to!string(t); }

T clamp01(T)(T t) {
	if (t < 0) return 0;
	if (t > 1) return 1;
	return t;
 }


struct RGBA {
	ubyte r;
	ubyte g;
	ubyte b;
	this(ubyte r_, ubyte g_, ubyte b_) {
		this.r = r_;
		this.g = g_;
		this.b = b_;
	}
	// multiply by a float
	RGBA opBinary(string op : "*")(float f) const {
		return RGBA(
			cast(ubyte)(r*f),
			cast(ubyte)(g*f),
			cast(ubyte)(b*f)
		);
	}

	uint toRgba() {
		return
			(r << 24)
			+ (g << 16)
			+ (b << 8)
			+ 0xff;
	}
	uint toAbgr() {
		return r
			+ (g << 8)
			+ (b << 16)
			+ 0xff000000;
	}

	alias toRgba this;
}


// Access the array while wrapping around the edges
T wrap(T)(T[] arr, int i) {
	return arr[(i + arr.length) % arr.length];
}



// install a telnet logger
public import std.experimental.logger;
import std.experimental.logger.core;
import std.socket, std.stdio, std.concurrency;
import std.container.dlist;
import core.thread.osthread;

class NetworkLogger : Logger {
	private TcpSocket serverSocket;
	private DList!Socket clients;

	this(LogLevel lv) {
		super(lv);
		serverSocket = new TcpSocket();
		serverSocket.bind(new InternetAddress("127.0.0.1", 1234));
		serverSocket.listen(3);

		auto t = new Thread(&acceptClients);
		t.start();
	}

	void acceptClients() {
		while(true)
		{
			auto clientSocket = serverSocket.accept();
			clients.insertBack(clientSocket);
			clientSocket.send("Welcome to volume normalizer!\r\n");
		}
	}


	override void writeLogMsg(ref LogEntry payload) {
		string message = payload.msg;
		foreach(ref sock; clients) {
			sock.send(message ~ "\r\n");
		}
	}
}

class NullLogger : Logger {
	this(LogLevel lv) {
		super(lv);
	}

	override void writeLogMsg(ref LogEntry payload) {
	}
}
shared static this() {
	try {
		debug {
			//sharedLog = new NullLogger(LogLevel.all);
		}
		else {
			sharedLog = new NullLogger(LogLevel.all);
		}
	}
	finally {}
}

