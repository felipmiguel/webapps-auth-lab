variable "solution_name" {
  type        = string
  description = "Name of the solution. This name will be used to compose the name of all resources deployed with this script"
  default     = "msiappis"
}

variable "location" {
  type    = string
  default = "westeurope"
}

variable "apps_tier" {
    type = string
    default = "Basic"  
}

variable "apps_size" {
    type = string
    default = "B1"  
}
