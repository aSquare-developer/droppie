# Postman

Импортируй коллекцию:

- [droppie-api.postman_collection.json](/Users/arturanissimov/Desktop/vapor/droppie/docs/postman/droppie-api.postman_collection.json)

Рекомендуемые collection variables:

- `baseUrl`: `http://127.0.0.1:8080`
- `username`: любой новый логин, например `postman_demo`
- `email`: email пользователя, например `postman_demo@example.com`
- `password`: например `StrongPass123`
- `newPassword`: например `StrongPass456`
- `verificationToken`: токен подтверждения email
- `resetToken`: токен сброса пароля
- `accessToken`: заполнится автоматически после `Register`, `Login` или `Refresh Tokens`
- `refreshToken`: заполнится автоматически после `Register`, `Login` или `Refresh Tokens`
- `userId`: заполнится автоматически после `Register` или `Login`
- `routeId`: заполнится автоматически после `Create Route`

Рекомендуемый порядок запросов:

1. `Health / Live`
2. `Health / Ready`
3. `Auth / Register`
4. Забрать verification token из логов приложения
5. `Auth / Verify Email`
6. `Auth / Login`
7. `Auth / Me`
8. `Profile / Upsert Profile`
9. `Profile / Get Profile`
10. `Routes / Create Route`
11. `Routes / List Routes`
12. `Auth / Refresh Tokens`
13. `Auth / Forgot Password`
14. Забрать reset token из логов приложения
15. `Auth / Reset Password`
16. `Auth / Login With New Password`
17. `Routes / Delete Route` при необходимости

Что важно:

- Логин теперь работает по `email`, а не по `username`.
- После `Register` пользователь создаётся, но не может полноценно войти, пока не подтвердит email.
- В текущем dev-режиме письмо не отправляется наружу: `verification token` и `reset token` пишутся в логи приложения через `EmailService`.
- `Create Route` может вернуть `reason`, что расчёт дистанции временно недоступен, если Redis или Google Routes API не настроены.
- `Generate Routes PDF` сработает только если у маршрутов уже есть `distance` и установлен `wkhtmltopdf`.
- `Delete Route` требует, чтобы `routeId` уже был записан в переменную коллекции. После `Create Route` это делается автоматически тест-скриптом.
