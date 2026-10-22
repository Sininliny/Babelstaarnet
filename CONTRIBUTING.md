# Developing Babelstårnet

Start with [the platform development guide](docs/DEVELOPMENT.md). It maps the
two applications, their shared contracts, build commands and validation tools.
Windows visual conventions are described in [the Windows design guide](docs/WINDOWS_DESIGN.md).

Run `python Scripts/check-repository.py` before platform checks. Changes to
reading, language data or learning behavior should pass both native CI jobs.
UI changes should include production renders in the relevant appearance modes.
Performance changes should include comparable measurements and their limits.

Keep downloaded models, user data, screenshots, measurements and build outputs
out of Git. Reading and speech must continue to work without internet access;
engine downloads belong only to explicit setup actions. Public news is a separate,
default-off network feature; its native adapters must never receive private
screen content or send learning inputs to a remote service.
