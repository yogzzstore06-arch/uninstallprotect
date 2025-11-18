#!/bin/bash
# ===============================================================
# 🛡️  Uninstall Script Proteksi ServerDeletionService Anti Hapus Server
# ===============================================================

REMOTE_PATH="/var/www/pterodactyl/app/Services/Servers/ServerDeletionService.php"
TIMESTAMP=$(date -u +"%Y-%m-%d-%H-%M-%S")

echo ""
echo "🚀 Memulai proses uninstall proteksi ServerDeletionService..."
echo "🕒 Tanggal: $TIMESTAMP"
echo "---------------------------------------------------------------"

# Pastikan direktori tujuan ada
if [ ! -d "$(dirname "$REMOTE_PATH")" ]; then
    echo "📁 Direktori tidak ditemukan, membuat direktori baru..."
    if mkdir -p "$(dirname "$REMOTE_PATH")"; then
        chmod 755 "$(dirname "$REMOTE_PATH")"
        echo "✅ Direktori berhasil dibuat."
    else
        echo "❌ Gagal membuat direktori. Periksa izin akses (root/sudo)!"
        exit 1
    fi
fi

# Backup file lama jika ada
if [ -f "$REMOTE_PATH" ]; then
    BACKUP_PATH="${REMOTE_PATH}.${TIMESTAMP}.bak"
    echo "🗂️ Membuat backup file lama ke: $BACKUP_PATH"
    cp "$REMOTE_PATH" "$BACKUP_PATH" || {
        echo "⚠️ Gagal membuat backup file. Proses dihentikan."
        exit 1
    }
fi

# Tulis ulang file ServerDeletionService.php asli (tanpa proteksi)
cat > "$REMOTE_PATH" <<'EOF'
<?php

namespace Pterodactyl\Services\Servers;

use Illuminate\Http\Response;
use Pterodactyl\Models\Server;
use Illuminate\Support\Facades\Log;
use Illuminate\Database\ConnectionInterface;
use Pterodactyl\Repositories\Wings\DaemonServerRepository;
use Pterodactyl\Services\Databases\DatabaseManagementService;
use Pterodactyl\Exceptions\Http\Connection\DaemonConnectionException;

class ServerDeletionService
{
    protected bool $force = false;

    /**
     * ServerDeletionService constructor.
     */
    public function __construct(
        private ConnectionInterface $connection,
        private DaemonServerRepository $daemonServerRepository,
        private DatabaseManagementService $databaseManagementService
    ) {
    }

    /**
     * Set if the server should be forcibly deleted from the panel (ignoring daemon errors) or not.
     */
    public function withForce(bool $bool = true): self
    {
        $this->force = $bool;

        return $this;
    }

    /**
     * Delete a server from the panel and remove any associated databases from hosts.
     *
     * @throws \Throwable
     * @throws \Pterodactyl\Exceptions\DisplayException
     */
    public function handle(Server $server): void
    {
        try {
            $this->daemonServerRepository->setServer($server)->delete();
        } catch (DaemonConnectionException $exception) {
            if (!$this->force && $exception->getStatusCode() !== Response::HTTP_NOT_FOUND) {
                throw $exception;
            }

            Log::warning($exception);
        }

        $this->connection->transaction(function () use ($server) {
            foreach ($server->databases as $database) {
                try {
                    $this->databaseManagementService->delete($database);
                } catch (\Exception $exception) {
                    if (!$this->force) {
                        throw $exception;
                    }

                    $database->delete();

                    Log::warning($exception);
                }
            }

            $server->delete();
        });
    }
}

EOF

# Pastikan file berhasil ditulis
if [ -f "$REMOTE_PATH" ]; then
    chmod 644 "$REMOTE_PATH"
    echo "✅ Uninstall proteksi ServerDeletionService berhasil!"
    echo "📂 Lokasi file: $REMOTE_PATH"
    echo "---------------------------------------------------------------"
else
    echo "❌ Gagal menulis ulang file ServerDeletionService.php!"
    exit 1
fi
