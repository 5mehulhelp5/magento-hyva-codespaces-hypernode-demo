#!/bin/bash

echo "============ Magento Codespace Status =========="

echo "Services Status:"
echo "- MySQL: $(sudo service mysql status | grep -q 'running' && echo 'Running' || echo 'Stopped')"
echo "- Nginx: $(sudo service nginx status | grep -q 'running' && echo 'Running' || echo 'Stopped')"
echo "- Supervisor: $(sudo service supervisor status | grep -q 'running' && echo 'Running' || echo 'Stopped')"
echo "- Redis: $(redis-cli ping 2>/dev/null || echo 'Not responding')"
echo "- PHP-FPM: $(pgrep -f php-fpm >/dev/null && echo 'Running' || echo 'Stopped')"

echo ""
echo "URLs:"
if [ -n "${CODESPACE_NAME:-}" ]; then
  echo "  Frontend: https://${CODESPACE_NAME}-8080.app.github.dev/"
  echo "  Admin: https://${CODESPACE_NAME}-8080.app.github.dev/admin"
  echo "  Mailpit: https://${CODESPACE_NAME}-8025.app.github.dev/"
else
  echo "  Frontend: http://localhost:8080/"
  echo "  Admin: http://localhost:8080/admin"
  echo "  Mailpit: http://localhost:8025/"
fi

echo ""
echo "To restart services: .devcontainer/start_services.sh"