SWIFTFLAGS=--disable-sandbox --cache-path .build/spm-cache

.PHONY: probe build test app run restore clean

probe:
	swift build $(SWIFTFLAGS) --target DaylightProbe
	.build/debug/DaylightProbe --apply --hold 4

build:
	swift build $(SWIFTFLAGS) -c release --product Daylight

test:
	swift build $(SWIFTFLAGS) --product DaylightChecks
	.build/debug/DaylightChecks

app: build
	./Scripts/package-app.sh

run: app
	open dist/Daylight.app

restore:
	swift build $(SWIFTFLAGS) --target DaylightProbe
	.build/debug/DaylightProbe --restore-only

clean:
	rm -rf .build dist
