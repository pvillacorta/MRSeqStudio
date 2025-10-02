"""
    get_db_connection()

Establece una conexión con la base de datos utilizando la configuración 
almacenada en el archivo externo db_config.toml
"""
function get_db_connection()
    # Ruta al archivo de configuración
    config_path = joinpath(@__DIR__, "db_config.toml")
    
    # Verificar si el archivo existe
    if !isfile(config_path)
        error("Archivo de configuración no encontrado: $config_path")
    end
    
    # Leer la configuración
    try
        db_config = TOML.parsefile(config_path)
        
        # Establecer la conexión
        return DBInterface.connect(
            MySQL.Connection,
            db_config["host"],
            db_config["user"],
            db_config["password"];
            db = db_config["database"],
            port = db_config["port"]
        )
    catch e
        error("Error al conectar a la base de datos: $e")
    end
end
