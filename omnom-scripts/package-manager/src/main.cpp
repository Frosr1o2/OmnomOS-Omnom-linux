// omnom-pkg - entry point and command dispatch.

#include "common.hpp"

#include <iostream>
#include <string>
#include <vector>

namespace {

std::string basename_of(const std::string &path) {
    const auto slash = path.rfind('/');
    return slash == std::string::npos ? path : path.substr(slash + 1);
}

void print_usage() {
    std::cout << "Usage: omnom-pkg <command> [options]\n\n"
                 "Commands:\n"
                 "  install   install packages or inspect the system\n"
                 "  remove    remove packages installed through Omnom\n"
                 "  upgrade   update packages and manage generations\n"
                 "  rollback  switch the active generation\n\n"
                 "Run 'omnom-pkg <command> --help' for command options.\n";
}

}  // namespace

int main(int argc, char **argv) {
    if (argc < 2) {
        print_usage();
        return 2;
    }

    std::string command = argv[1];
    std::vector<std::string> args;
    for (int index = 2; index < argc; ++index) {
        args.emplace_back(argv[index]);
    }

    // The launcher scripts pass the command explicitly; accept invocation by
    // program name as well so the binary can be symlinked directly.
    if (command != "install" && command != "remove" && command != "upgrade" &&
        command != "rollback") {
        const std::string name = basename_of(command);
        if (name == "omnom-install") {
            command = "install";
        } else if (name == "omnom-remove") {
            command = "remove";
        } else if (name == "omnom-upgrade") {
            command = "upgrade";
        } else if (name == "omnom-rollback") {
            command = "rollback";
        } else if (command == "--help" || command == "-h" || command == "help") {
            print_usage();
            return 0;
        } else {
            std::cerr << "[omnom] unknown command '" << command << "'\n\n";
            print_usage();
            return 2;
        }
    }

    try {
        if (command == "install") {
            return omnom::cmd_install(args);
        }
        if (command == "remove") {
            return omnom::cmd_remove(args);
        }
        if (command == "upgrade") {
            return omnom::cmd_upgrade(args);
        }
        return omnom::cmd_rollback(args);
    } catch (const omnom::Error &error) {
        std::cerr << "[omnom] error: " << error.what() << '\n';
        return 1;
    } catch (const std::filesystem::filesystem_error &error) {
        std::cerr << "[omnom] filesystem error: " << error.what() << '\n';
        return 1;
    } catch (const std::exception &error) {
        std::cerr << "[omnom] unexpected error: " << error.what() << '\n';
        return 1;
    }
}
