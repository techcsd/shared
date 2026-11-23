import { Component, signal } from '@angular/core';
import { ConfigActivos } from '../../components/configuracion/config-activos/config-activos';
import { ConfigCorreos } from '../../components/configuracion/config-correos/config-correos';
import { ConfigDestinos } from '../../components/configuracion/config-destinos/config-destinos';
import { ConfigGrupo } from '../../components/configuracion/config-grupo/config-grupo';
import { ConfigTipos } from '../../components/configuracion/config-tipos/config-tipos';
import { t } from '../../core/i18n/i18n';

type Seccion = 'grupo' | 'activos' | 'destinos' | 'tipos' | 'correos';

/** Configuración (SA17): bote/activo, motores, destinos, tarifas, correos y tipos de activo. Solo socios. */
@Component({
  selector: 'app-configuracion',
  standalone: true,
  imports: [ConfigGrupo, ConfigActivos, ConfigDestinos, ConfigTipos, ConfigCorreos],
  templateUrl: './configuracion.html',
  styleUrl: './configuracion.scss',
})
export class ConfiguracionPage {
  t = t;
  seccion = signal<Seccion>('activos');
  secciones: { id: Seccion; etiqueta: () => string }[] = [
    { id: 'activos', etiqueta: () => t('config.tab.activos') },
    { id: 'destinos', etiqueta: () => t('config.tab.destinos') },
    { id: 'tipos', etiqueta: () => t('config.tab.tipos') },
    { id: 'grupo', etiqueta: () => t('config.tab.grupo') },
    { id: 'correos', etiqueta: () => t('config.tab.correos') },
  ];
}
