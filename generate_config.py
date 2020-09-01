import json
import sys
from types import SimpleNamespace as Namespace
import argparse
import os
from string import Template

def parseArguments():
    parser = argparse.ArgumentParser(
        description="Generate telegraf postgres monitoring config from templates"
    )    
    parser.add_argument("--db_user", type=str, help="Database user to use in telegraf configuration", required=True)
    parser.add_argument("--db_user_password", type=str, help="Database user password", required=True)
    parser.add_argument("--dryrun", action="store_true", default=False, help = "Dry run migrations. Only prints the changes. Default false")
    return parser.parse_args()


def main():
    args = parseArguments()
    dbUser = args.db_user
    dbUserPassword = args.db_user_password
    dryrun = args.dryrun


    databaseInstances = json.loads(open("databases.json", "r").read(), object_hook=lambda d: Namespace(**d))
    perInstanceTemplate = Template(open("per_instance_template.toml", "r").read())
    perDatabaseTemplate = Template(open("per_database_template.toml", "r").read())

    for databaseInstance in databaseInstances:        
        instanceConfigMap = dict(
            DbInstanceName = databaseInstance.instanceName,
            DbInstanceHostname = databaseInstance.hostname,
            DbUser = dbUser,
            DbUserPassword = dbUserPassword
        )

        instanceConfig = perInstanceTemplate.substitute(instanceConfigMap)

        for database in databaseInstance.databases:
            databaseConfigMap = dict(instanceConfigMap)
            databaseConfigMap["DatabaseName"] = database.name
            databaseConfig = perDatabaseTemplate.substitute(databaseConfigMap)
            instanceConfig += "\n" + databaseConfig

        if not dryrun:
            configFile = open(databaseInstance.instanceName + ".conf", "w")
            configFile.write(instanceConfig)
        else:
            print(configFile)




if __name__ == "__main__":
    main()
