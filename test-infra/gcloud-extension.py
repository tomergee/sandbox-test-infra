#!/usr/bin/python3
import subprocess
import sys

# Function to invoke a command and filter its stdout and stderr
def invoke_command(command):
    # Execute the command
    process = subprocess.Popen(command, stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True)
    stdout, stderr = process.communicate()

    # Filter stdout and stderr (example: remove empty lines)
    filtered_stdout = '\n'.join(line for line in stdout.splitlines() if line.strip())
    filtered_stderr = '\n'.join(line for line in stderr.splitlines() if line.strip())

    return filtered_stdout, filtered_stderr, process

# Example usage
if __name__ == "__main__":
    command = ['/google-cloud-sdk/bin/gcloud']
    command.extend(sys.argv[1:])  # Replace with your desired command
    stdout, stderr, process  = invoke_command(command)

    print('exit code:', process.returncode)
    print('gcloud stdout:\n', stdout)
    print('gcloud stderr:\n', stderr)

    # TODO(balamut): Handle other error kinds with custom exit codes
    # that could be more useful.
    if stdout.find('GCE_STOCKOUT') >  -1 or stderr.find('GCE_STOCKOUT') >  -1:
        print('Stockout string detected in gcloud output...')
        if process.returncode != 0:
            print('... and exit code was non-zero. Returning magic exit code\n')
            sys.exit(103)
        else:
            print('... but the exit code was zero. So returning process exit code, namely 0\n')
            sys.exit(process.returncode)
    else:
        print('Stockout string not detected in gcloud output, returning original exit code')
        sys.exit(process.returncode)