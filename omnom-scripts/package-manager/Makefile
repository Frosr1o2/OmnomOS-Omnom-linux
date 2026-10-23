# Omnom package manager build.
#
# The binary targets a minimal LFS-based system:
#   * no runtime dependencies beyond libc (libstdc++ and libgcc are linked in
#     statically so the base system does not need them),
#   * -mtune=generic instead of -march=native so one binary runs on every
#     supported CPU,
#   * unused sections are garbage collected and the installed binary is
#     stripped to keep the image small.

CXX      ?= g++
PREFIX   ?= /usr
BINDIR   ?= $(PREFIX)/bin
LIBEXECDIR ?= $(PREFIX)/libexec/omnom

CPPFLAGS ?=
CXXFLAGS ?= -std=c++17 -O2 -DNDEBUG -mtune=generic \
            -ffunction-sections -fdata-sections \
            -Wall -Wextra -Wpedantic
LDFLAGS  ?= -Wl,--gc-sections -static-libstdc++ -static-libgcc
LDLIBS   ?=

TARGET   := omnom-pkg
SOURCES  := $(wildcard src/*.cpp)
OBJECTS  := $(SOURCES:.cpp=.o)

.PHONY: all clean install uninstall test size

all: $(TARGET)

$(TARGET): $(OBJECTS)
	$(CXX) $(CXXFLAGS) $(LDFLAGS) -o $@ $(OBJECTS) $(LDLIBS)

src/%.o: src/%.cpp src/common.hpp
	$(CXX) $(CPPFLAGS) $(CXXFLAGS) -c -o $@ $<

size: $(TARGET)
	@strip -o /tmp/omnom-pkg.stripped $(TARGET)
	@wc -c $(TARGET) /tmp/omnom-pkg.stripped | sed 's/^/  /'
	@rm -f /tmp/omnom-pkg.stripped

test: $(TARGET)
	sh tests/run-tests.sh

install: $(TARGET)
	install -d $(DESTDIR)$(LIBEXECDIR)
	install -s -m755 $(TARGET) $(DESTDIR)$(LIBEXECDIR)/$(TARGET)
	install -d $(DESTDIR)$(BINDIR)
	for command in install remove upgrade rollback; do \
		install -m755 omnom-$$command $(DESTDIR)$(BINDIR)/omnom-$$command; \
	done

uninstall:
	rm -f $(DESTDIR)$(LIBEXECDIR)/$(TARGET)
	for command in install remove upgrade rollback; do \
		rm -f $(DESTDIR)$(BINDIR)/omnom-$$command; \
	done

clean:
	rm -f $(OBJECTS) $(TARGET)
