"""
    get_db_connection()

Establishes a database connection using the configuration 
stored in the external db_config.toml file
"""
function get_db_connection()
    # Path to the configuration file
    config_path = joinpath(@__DIR__, "db_config.toml")
    
    # Check if the file exists
    if !isfile(config_path)
        error("Configuration file not found: $config_path")
    end
    
    # Read the configuration
    try
        db_config = TOML.parsefile(config_path)
        
        # Establish the connection
        return DBInterface.connect(
            MySQL.Connection,
            db_config["host"],
            db_config["user"],
            db_config["password"];
            db = db_config["database"],
            port = db_config["port"]
        )
    catch e
        error("Error connecting to database: $e")
    end
end
