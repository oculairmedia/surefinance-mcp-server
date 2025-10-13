# frozen_string_literal: true

module SurefinanceMCP
  module Models
    module Concerns
      module FamilyScoped
        extend ActiveSupport::Concern

        class_methods do
          def for_family(family_id)
            where(family_id: family_id)
          end

          def find_for_family!(family_id, id)
            for_family(family_id).find(id)
          end
        end
      end
    end
  end
end
