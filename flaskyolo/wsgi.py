# add project directory
import sys
project_home = "/app"
if project_home not in sys.path:
    sys.path = [project_home] + sys.path


from flaskyolo.app import app as application

