# Part of a cron job to clear expired storage from the TempStorage API

require 'common'
require 'active_support/time'

info "Clearing expired storage..."
TempStorage.clear_expired
info "Done!"
