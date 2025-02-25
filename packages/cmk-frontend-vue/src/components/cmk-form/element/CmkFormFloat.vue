<script setup lang="ts">
import { computed, ref } from 'vue'
import { is_float, validate_value, type ValidationMessages } from '@/utils'
import { FormValidation } from '@/components/cmk-form/'
import type { VueFloat } from '@/vue_formspec_components'

const props = defineProps<{
  spec: VueFloat
  validation: ValidationMessages
}>()

const data = defineModel<number>('data', { required: true })
const local_validation = ref<ValidationMessages | null>(null)

const emit = defineEmits<{
  (e: 'update:data', value: number | string): void
}>()

const value = computed({
  get() {
    return data.value
  },
  set(value: unknown) {
    local_validation.value = []
    let emitted_value: string | number
    if (is_float(value as string)) {
      emitted_value = parseFloat(value as string)
    } else {
      emitted_value = value as string
    }
    validate_value(emitted_value, props.spec.validators!).forEach((error) => {
      local_validation.value = [{ message: error, location: [''] }]
    })
    emit('update:data', emitted_value)
  }
})

const validation = computed(() => {
  // If the local validation was never used (null), return the props.validation (backend validation)
  if (local_validation.value === null) {
    return props.validation
  }
  return local_validation.value
})

const unit = computed(() => {
  return props.spec.unit || ''
})
</script>

<template>
  <input v-model="value" class="number" type="text" />
  <span v-if="unit" class="vs_floating_text">{{ unit }}</span>
  <FormValidation :validation="validation"></FormValidation>
</template>
