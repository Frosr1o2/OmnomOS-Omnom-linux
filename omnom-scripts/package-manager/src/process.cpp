// Process execution helpers.

#include "common.hpp"

#include <fcntl.h>
#include <sys/wait.h>
#include <unistd.h>

#include <cerrno>
#include <cstdlib>
#include <cstring>
#include <iostream>
#include <sstream>

namespace omnom {
namespace {

string join_argv(const vector<string> &argv) {
    string result;
    for (const auto &part : argv) {
        if (!result.empty()) {
            result += ' ';
        }
        result += part;
    }
    return result;
}

vector<char *> to_c_argv(const vector<string> &argv) {
    vector<char *> result;
    result.reserve(argv.size() + 1);
    for (const auto &part : argv) {
        result.push_back(const_cast<char *>(part.c_str()));
    }
    result.push_back(nullptr);
    return result;
}

}  // namespace

bool Runner::which(const string &program) const {
    if (program.empty()) {
        return false;
    }
    if (program.find('/') != string::npos) {
        return access(program.c_str(), X_OK) == 0;
    }
    const char *path_env = std::getenv("PATH");
    const string path = path_env ? path_env : "/usr/local/bin:/usr/bin:/bin";
    std::stringstream stream(path);
    string dir;
    while (std::getline(stream, dir, ':')) {
        if (dir.empty()) {
            dir = ".";
        }
        const fs::path candidate = fs::path(dir) / program;
        if (access(candidate.c_str(), X_OK) == 0) {
            return true;
        }
    }
    return false;
}

RunResult Runner::run(const vector<string> &argv_input, bool mutate, bool capture) {
    RunResult result;
    if (argv_input.empty()) {
        return result;
    }

    vector<string> argv = argv_input;
    if (mutate && geteuid() != 0 && which("sudo")) {
        argv.insert(argv.begin(), "sudo");
    }
    const string printed = join_argv(argv);

    if (dry_run_) {
        std::cout << "[dry-run] " << printed << '\n';
        return result;
    }
    if (!capture) {
        std::cout << "[exec] " << printed << '\n';
        std::cout.flush();
    }

    int pipe_fds[2] = {-1, -1};
    if (capture && pipe(pipe_fds) != 0) {
        throw Error("pipe() failed: " + string(std::strerror(errno)));
    }

    const pid_t pid = fork();
    if (pid < 0) {
        throw Error("fork() failed: " + string(std::strerror(errno)));
    }

    if (pid == 0) {
        if (capture) {
            dup2(pipe_fds[1], STDOUT_FILENO);
            const int devnull = open("/dev/null", O_WRONLY);
            if (devnull >= 0) {
                dup2(devnull, STDERR_FILENO);
            }
            close(pipe_fds[0]);
            close(pipe_fds[1]);
        }
        auto c_argv = to_c_argv(argv);
        execvp(c_argv[0], c_argv.data());
        _exit(127);
    }

    if (capture) {
        close(pipe_fds[1]);
        char buffer[4096];
        ssize_t count = 0;
        while ((count = read(pipe_fds[0], buffer, sizeof buffer)) > 0) {
            result.output.append(buffer, static_cast<size_t>(count));
        }
        close(pipe_fds[0]);
    }

    int status = 0;
    while (waitpid(pid, &status, 0) < 0 && errno == EINTR) {
    }
    if (WIFEXITED(status)) {
        result.status = WEXITSTATUS(status);
    } else if (WIFSIGNALED(status)) {
        result.status = 128 + WTERMSIG(status);
    } else {
        result.status = 1;
    }
    return result;
}

RunResult Runner::shell(const string &script, const fs::path &cwd,
                        const vector<std::pair<string, string>> &env, bool mutate) {
    RunResult result;
    if (dry_run_) {
        std::cout << "[dry-run] (cd " << cwd.string() << " && " << script << ")\n";
        return result;
    }
    std::cout << "[exec] (cd " << cwd.string() << " && " << script << ")\n";
    std::cout.flush();

    const pid_t pid = fork();
    if (pid < 0) {
        throw Error("fork() failed: " + string(std::strerror(errno)));
    }
    if (pid == 0) {
        if (chdir(cwd.c_str()) != 0) {
            _exit(126);
        }
        for (const auto &entry : env) {
            setenv(entry.first.c_str(), entry.second.c_str(), 1);
        }
        execl("/bin/sh", "sh", "-c", script.c_str(), static_cast<char *>(nullptr));
        _exit(127);
    }

    int status = 0;
    while (waitpid(pid, &status, 0) < 0 && errno == EINTR) {
    }
    (void)mutate;
    if (WIFEXITED(status)) {
        result.status = WEXITSTATUS(status);
    } else if (WIFSIGNALED(status)) {
        result.status = 128 + WTERMSIG(status);
    } else {
        result.status = 1;
    }
    return result;
}

}  // namespace omnom
