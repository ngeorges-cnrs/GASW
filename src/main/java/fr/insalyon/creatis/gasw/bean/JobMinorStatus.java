/* Copyright CNRS-CREATIS
 *
 * Rafael Ferreira da Silva
 * rafael.silva@creatis.insa-lyon.fr
 * http://www.rafaelsilva.com
 *
 * This software is a grid-enabled data-driven workflow manager and editor.
 *
 * This software is governed by the CeCILL  license under French law and
 * abiding by the rules of distribution of free software.  You can  use,
 * modify and/ or redistribute the software under the terms of the CeCILL
 * license as circulated by CEA, CNRS and INRIA at the following URL
 * "http://www.cecill.info".
 *
 * As a counterpart to the access to the source code and  rights to copy,
 * modify and redistribute granted by the license, users are provided only
 * with a limited warranty  and the software's author,  the holder of the
 * economic rights,  and the successive licensors  have only  limited
 * liability.
 *
 * In this respect, the user's attention is drawn to the risks associated
 * with loading,  using,  modifying and/or developing or reproducing the
 * software by the user in light of its specific status of free software,
 * that may mean  that it is complicated to manipulate,  and  that  also
 * therefore means  that it is reserved for developers  and  experienced
 * professionals having in-depth computer knowledge. Users are therefore
 * encouraged to load and test the software's suitability as regards their
 * requirements in conditions enabling the security of their systems and/or
 * data to be ensured and,  more generally, to use and operate it in the
 * same conditions as regards security.
 *
 * The fact that you are presently reading this means that you have had
 * knowledge of the CeCILL license and that you accept its terms.
 */
package fr.insalyon.creatis.gasw.bean;

import fr.insalyon.creatis.gasw.execution.GaswMinorStatus;
import java.util.Date;
import jakarta.persistence.*;
import org.hibernate.annotations.GenericGenerator;

/**
 *
 * @author Rafael Ferreira da Silva
 */
@Entity
@NamedQueries({
    @NamedQuery(name = "MinorStatus.findCheckpointById", query = "FROM "
    + "JobMinorStatus j WHERE j.job.id = :jobId AND (j.status = :checkpointInit "
    + "OR j.status = :checkpointUpload OR j.status = :checkpointEnd) ORDER BY j.date"),
    @NamedQuery(name = "MinorStatus.findExecutionById", query = "FROM "
    + "JobMinorStatus j WHERE j.job.id = :jobId AND (j.status = :start "
    + "OR j.status = :background OR j.status = :input OR j.status = :application "
    + "OR j.status = :output OR j.status = :finished) ORDER BY j.date"),
    @NamedQuery(name = "MinorStatus.dateDiff", query = "FROM "
    + "JobMinorStatus j WHERE j.job.id = :jobId AND (j.status = :start "
    + "OR j.status = :end) ORDER BY j.date")
})
@Table(name = "JobsMinorStatus")
public class JobMinorStatus {

    private int statusId;
    private Job job;
    private GaswMinorStatus status;
    private Date date;

    public JobMinorStatus() {
    }

    public JobMinorStatus(Job job, GaswMinorStatus status, Date date) {
        this.job = job;
        this.status = status;
        this.date = date;
    }

    @Id
    @GeneratedValue(generator = "increment")
    @GenericGenerator(name = "increment", strategy = "increment")
    public int getStatusId() {
        return statusId;
    }

    @Temporal(TemporalType.TIMESTAMP)
    @Column(name = "event_date")
    public Date getDate() {
        return date;
    }

    @ManyToOne
    @JoinColumn(name = "id")
    public Job getJob() {
        return job;
    }

    @Enumerated(EnumType.STRING)
    @Column(name = "minor_status")
    public GaswMinorStatus getStatus() {
        return status;
    }

    public void setStatusId(int statusId) {
        this.statusId = statusId;
    }

    public void setDate(Date date) {
        this.date = date;
    }

    public void setJob(Job job) {
        this.job = job;
    }

    public void setStatus(GaswMinorStatus status) {
        this.status = status;
    }
}
