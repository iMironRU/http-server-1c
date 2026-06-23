// Раздача OpenAPI спецификации и Swagger UI.
// URL: /<base>/hs/swagger/{File}
//   GET /swagger/             -> Swagger UI HTML
//   GET /swagger/index.html   -> Swagger UI HTML
//   GET /swagger/swagger.json -> сгенерированная OpenAPI 3.0 спецификация

Функция FileGet(Запрос)

	Возврат http_SwaggerЗапросы.ОбработатьЗапросФайла(Запрос);

КонецФункции
