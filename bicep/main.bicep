param solution_name string = 'demo1'
param service_plan_sku string = 'F1'
 
var plan_name = 'plan-${solution_name}'
var webapi1_name = 'app-${solution_name}-api1'
var webapi2_name = 'app-${solution_name}-api2'

resource appServicePlan 'Microsoft.Web/serverfarms@2020-12-01' = {
  name: plan_name
  location: resourceGroup().location
  sku: {
    name: service_plan_sku
    capacity: 1
  }
}

resource webapi1 'Microsoft.Web/sites@2018-11-01' = {
  name: webapi1_name
  location: resourceGroup().location
  tags: {
    'hidden-related:${resourceGroup().id}/providers/Microsoft.Web/serverfarms/appServicePlan': 'Resource'
  }
  properties: {
    serverFarmId: appServicePlan.id
  }
}


resource webapi2 'Microsoft.Web/sites@2018-11-01' = {
  name: webapi2_name
  location: resourceGroup().location
  tags: {
    'hidden-related:${resourceGroup().id}/providers/Microsoft.Web/serverfarms/appServicePlan': 'Resource'
  }
  properties: {
    serverFarmId: appServicePlan.id
  }
}
