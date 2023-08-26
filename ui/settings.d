module settings;

struct Settings {
	string name;
	int avgLength;
	int numBars;
	float limiterOffset;
	float limiterWidth;
	int limiterAttack;
	int limiterHold;
	float limiterDecay;

	static const Settings generic = Settings(
		"Generic",
		15, 15,
		1.2, 2.0,
		0,
		1000, 6
	);

	static const Settings movie = Settings(
		"Movie",
		8, 8,
		1.4, 2.1,
		0,
		1500, 1
	);

	static const Settings conference = Settings(
		"Online call",
		20, 10,
		-8.0, 1.3,
		200,
		1300, 3
	);

	static const Settings conference2 = Settings(
		"Conversation Flat",
		20, 10,
		-8.0, 1.3,
		20,
		200, 4
	);

	static const Settings music = Settings(
		"Music",
		20, 30,
		1.7, 2.0,
		100,
		3000, 3
	);

	static const Settings*[] all = [
		&generic,
		&movie,
		&conference,
		&music
	];
}

